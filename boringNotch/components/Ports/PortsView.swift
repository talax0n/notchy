//
//  PortsView.swift
//  boringNotch
//
// Adapted from portside by guneysol (MIT), https://github.com/guneysol/portside.
// See THIRD_PARTY_LICENSES.
//

import AppKit
import SwiftUI

struct PortsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var store = PortsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            if store.groups.isEmpty {
                PortsEmptyState(store: store)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.groups) { GroupSection(group: $0, store: store) }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.never)
            }
            Footer(store: store)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { vm.isHoveringScrollView = $0 }
        .task { await store.poll() }
    }
}

private struct PortsEmptyState: View {
    @ObservedObject var store: PortsStore

    var body: some View {
        VStack(spacing: 4) {
            if store.helperUnavailable {
                Text("Can't reach the helper").font(.system(size: 13, weight: .medium))
                Text("Port scanning runs in BoringNotchXPCHelper.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing running").font(.system(size: 13, weight: .medium))
                Text("Dev servers and local services show up here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if store.hiddenCount > 0, !store.showSystem {
                    let n = store.hiddenCount
                    Button(n == 1 ? "Show 1 system listener" : "Show \(n) system listeners") { store.showSystem = true }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .padding(.top, 4)
                }
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GroupSection: View {
    let group: ProcessGroup
    @ObservedObject var store: PortsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(group.processes) { ProcessRow(process: $0, store: store) }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(group.title).fontWeight(.semibold).layoutPriority(1)
            if let branch = group.project?.branch {
                // Worktrees get a branch glyph: that is the one thing telling two checkouts of a repo apart.
                if group.project?.isWorktree == true {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .semibold))
                }
                Text(branch).lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .help(group.project.map { ($0.isWorktree ? "Git worktree at " : "") + Format.abbreviatingHome($0.root) }
              ?? "Processes outside a project folder")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Tinted icon for what a process is, so rows can be scanned by kind at a glance.
private struct KindTile: View {
    let kind: Kind

    private var tint: Color {
        switch kind {
        case .web: .blue
        case .database: .orange
        case .service: .purple
        case .runtime: .gray
        }
    }

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct ProcessRow: View {
    let process: DevProcess
    @ObservedObject var store: PortsStore
    @State private var hovering = false

    private var stopping: Bool { store.stopping.contains(process.pid) }

    var body: some View {
        HStack(spacing: 8) {
            KindTile(kind: process.kind)
                .padding(.trailing, 2)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(process.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .layoutPriority(1)
                    // Tells apart two "pnpm dev" rows in the same repo.
                    if let sub = process.subpath {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            HStack(spacing: 4) {
                ForEach(process.ports, id: \.number) { PortChip(port: $0, kind: process.kind) }
            }
            .fixedSize()

            // Only while it matters, so at rest the ports line up at the edge.
            if stopping || hovering {
                trailing.frame(width: 18, height: 18)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .opacity(stopping ? 0.5 : 1)
        .background(hovering ? Color.white.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(process.command)
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if process.canStop {
                Button("Stop") { store.stop([process]) }
                Button("Force Quit") { store.stop([process], force: true) }
            }
        }
    }

    /// The command truncates first; who started it and for how long stay readable.
    /// Scans that change nothing don't redraw, so the uptime ticks on its own, once a minute.
    private var detail: some View {
        HStack(spacing: 0) {
            Text(process.summary).lineLimit(1).truncationMode(.middle)
            TimelineView(.periodic(from: process.started, by: 60)) { context in
                let tail = [process.origin, Format.uptime(context.date.timeIntervalSince(process.started))]
                    .compactMap { $0 }.joined(separator: " · ")
                Text(verbatim: " · " + tail).lineLimit(1).fixedSize()
            }
            .layoutPriority(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var trailing: some View {
        if stopping {
            ProgressView().controlSize(.mini)
        } else if process.canStop {
            StopButton(name: process.name) { store.stop([process]) }
        } else if process.isContainerEngine {
            Image(systemName: "shippingbox")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help("Container ports. Stop containers from \(process.name), so it keeps running")
                .accessibilityLabel("Container ports")
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help("Owned by another user — stop it with sudo")
                .accessibilityLabel("Owned by another user")
        }
    }

    @ViewBuilder private var menu: some View {
        if process.kind == .web {
            ForEach(process.ports, id: \.number) { port in
                Button(String("Open localhost:\(port.number)")) { Actions.open(port) }
            }
        }
        ForEach(process.ports, id: \.number) { port in
            Button(String("Copy localhost:\(port.number)")) { Actions.copy("localhost:\(port.number)") }
        }
        Divider()
        if !process.cwd.isEmpty {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.cwd)])
            }
            Button("Copy Path") { Actions.copy(process.cwd) }
        }
        Button("Copy Command") { Actions.copy(process.command) }
        if let container = process.container {
            Button("Copy Container Name") { Actions.copy(container.name) }
        } else {
            Button("Copy PID") { Actions.copy("\(process.pid)") }
        }
        if process.canStop {
            Divider()
            Button("Stop") { store.stop([process]) }
            Button("Force Quit") { store.stop([process], force: true) }
        }
    }
}

/// Web ports are links (accent, open the browser); everything else is a neutral
/// chip that copies its address. Ports reachable from the network carry a glyph.
private struct PortChip: View {
    let port: ListenPort
    let kind: Kind
    @State private var copied = false
    @State private var hovering = false

    private var isLink: Bool { kind == .web }
    private var tint: Color { isLink ? .effectiveAccent : .white }

    var body: some View {
        Button {
            if isLink { Actions.open(port) } else {
                Actions.copy("localhost:\(port.number)")
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
            }
        } label: {
            HStack(spacing: 3) {
                if port.exposed {
                    Image(systemName: "network").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
                }
                // Keeps its width while "copied" shows, so nothing next to it jumps.
                Text(verbatim: ":\(port.number)")
                    .opacity(copied ? 0 : 1)
                    .overlay { if copied { Image(systemName: "checkmark").fontWeight(.bold) } }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(isLink ? AnyShapeStyle(Color.effectiveAccent) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(tint.opacity(hovering ? 0.18 : isLink ? 0.1 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help((isLink ? "Open in browser" : "Copy localhost:\(port.number)")
              + (port.exposed ? " · Reachable from your network (listening on all interfaces)" : ""))
        .accessibilityLabel(isLink ? "Open port \(port.number)" : "Copy port \(port.number)")
        .accessibilityHint(port.exposed ? "Reachable from your network" : "")
    }
}

private struct StopButton: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovering ? Color.red : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Stop \(name)")
        .accessibilityLabel("Stop \(name)")
    }
}

private struct Footer: View {
    @ObservedObject var store: PortsStore
    @State private var confirming = false

    /// "Stop 3 processes and 2 containers?"
    static func confirmation(_ rows: [DevProcess]) -> String {
        let containers = rows.filter { $0.container != nil }.count, processes = rows.count - containers
        let parts = [(processes, "process", "processes"), (containers, "container", "containers")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        return "Stop \(parts.joined(separator: " and "))?"
    }

    var body: some View {
        HStack(spacing: 2) {
            // Never system or app listeners (AirPlay, Spotify…) or Docker itself, even while they're shown.
            let stoppable = store.visible.filter { $0.canStop && !$0.isSystem }
            if confirming {
                Text(Self.confirmation(stoppable))
                    .foregroundStyle(.white)
                    .padding(.leading, 7)
                Spacer()
                Button("Cancel") { confirming = false }
                    .buttonStyle(FooterButtonStyle())
                Button("Stop All") {
                    store.stop(stoppable)
                    confirming = false
                }
                .buttonStyle(FooterButtonStyle(tint: .red))
                .fontWeight(.semibold)
            } else {
                if !stoppable.isEmpty {
                    Button("Stop All") {
                        confirming = true
                        Task { try? await Task.sleep(for: .seconds(4)); confirming = false }
                    }
                    .buttonStyle(FooterButtonStyle())
                    .help("Stop every process and container you own in this list")
                }
                Spacer()
                Button {
                    store.showSystem.toggle()
                } label: {
                    Label(store.hiddenCount > 0 && !store.showSystem ? "System (\(store.hiddenCount))" : "System",
                          systemImage: store.showSystem ? "eye" : "eye.slash")
                }
                .buttonStyle(FooterButtonStyle())
                .help(store.showSystem ? "Hide system & app listeners" : "Show system & app listeners")
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(FooterButtonStyle())
                .help("Refresh")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(height: 24)
    }
}

/// Subtle rounded highlight on hover, a little stronger while pressed.
private struct HoverChrome: ViewModifier {
    var tint: Color?
    var pressed = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint ?? (hovering ? Color.white : Color.secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((tint ?? .white).opacity(pressed ? 0.16 : hovering ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct FooterButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(HoverChrome(tint: tint, pressed: configuration.isPressed))
    }
}

private enum Actions {
    static func open(_ port: ListenPort) {
        if let url = URL(string: "http://localhost:\(port.number)") { NSWorkspace.shared.open(url) }
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
