//
//  PortsStore.swift
//  boringNotch
//
// Adapted from portside by guneysol (MIT), https://github.com/guneysol/portside.
// See THIRD_PARTY_LICENSES.
//

import Defaults
import Foundation

@MainActor
final class PortsStore: ObservableObject {
    static let shared = PortsStore()

    @Published private(set) var processes: [DevProcess] = [] { didSet { regroup() } }
    @Published private(set) var stopping: Set<Int32> = []
    @Published private(set) var helperUnavailable = false
    @Published var showSystem = Defaults[.portsShowSystem] {
        didSet {
            Defaults[.portsShowSystem] = showSystem
            regroup()
        }
    }

    @Published private(set) var visible: [DevProcess] = []
    @Published private(set) var groups: [ProcessGroup] = []
    var hiddenCount: Int { processes.count - visible.count }

    private var inFlight: Task<Void, Never>?
    /// When the scan behind `processes` started; Stop only signals pids at least that old.
    private var scannedAt = Date.distantPast

    private init() {}

    private func regroup() {
        visible = processes.filter { showSystem || !$0.isSystem }
        groups = Dictionary(grouping: visible) { $0.project?.root ?? "" }
            .map { root, procs in
                ProcessGroup(id: root, project: procs.first?.project,
                             processes: procs.sorted { ($0.ports.first?.number ?? 0) < ($1.ports.first?.number ?? 0) })
            }
            .sorted { a, b in
                // Projects alphabetically, loose services last.
                if (a.project == nil) != (b.project == nil) { return a.project != nil }
                let order = a.title.localizedStandardCompare(b.title)
                if order != .orderedSame { return order == .orderedAscending }
                if a.project?.isWorktree != b.project?.isWorktree { return a.project?.isWorktree == false }
                return a.id < b.id // stable order for same-named worktrees
            }
    }

    /// Runs while the Ports tab is on screen: SwiftUI cancels it when the tab
    /// changes or the notch closes.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2), tolerance: .seconds(0.2))
        }
    }

    /// Always reflects a scan started after the call. A caller arriving mid-scan
    /// waits for it, then shares one follow-up scan with anyone else who arrived meanwhile.
    func refresh() async {
        if let inFlight { await inFlight.value }
        if let inFlight { return await inFlight.value }
        let task = Task {
            // Taken before the helper reads the process table, so a pid reused mid-scan is never "ours".
            let started = Date()
            let fresh = await XPCHelperClient.shared.scanPorts(includeForeign: true)?.sorted { $0.pid < $1.pid }
            helperUnavailable = fresh == nil
            if let fresh {
                scannedAt = started
                if fresh != processes { processes = fresh }
            }
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    func stop(_ processes: [DevProcess], force: Bool = false) {
        let targets = processes.filter { !stopping.contains($0.pid) }
        guard !targets.isEmpty else { return }
        stopping.formUnion(targets.map(\.pid))
        let request = StopRequest(processes: targets, asOf: scannedAt)
        Task {
            _ = await XPCHelperClient.shared.stopProcesses(request, force: force)
            await refresh()
            stopping.subtract(targets.map(\.pid))
        }
    }
}
