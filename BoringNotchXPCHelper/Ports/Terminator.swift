// Adapted from portside by guneysol (MIT), https://github.com/guneysol/portside.
// See THIRD_PARTY_LICENSES.

import Foundation

enum Terminator {
    /// SIGTERM the tree, SIGKILL whatever is left after 3s. Only pids that already
    /// existed at `scanned` are signalled, so a pid reused since then is left alone.
    static func stop(_ p: DevProcess, force: Bool, asOf scanned: Date) async {
        guard !p.isContainerEngine else { return }
        if let container = p.container {
            // The engine waits up to 10s for the container; keep that off Swift's cooperative pool.
            await withCheckedContinuation { done in
                DispatchQueue.global(qos: .userInitiated).async {
                    Docker.stop(container, force: force)
                    done.resume()
                }
            }
            return
        }
        // brew services have KeepAlive — a plain kill just gets them restarted.
        if !force, let label = p.launchdLabel, label.hasPrefix("homebrew.mxcl."),
           let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile) {
            let name = String(label.dropFirst("homebrew.mxcl.".count))
            guard !name.isEmpty, !name.hasPrefix("-") else { return } // a label, never a flag like --all
            // brew can take seconds; keep it off Swift's small cooperative pool.
            await withCheckedContinuation { done in
                DispatchQueue.global(qos: .userInitiated).async {
                    Shell.run(brew, ["services", "stop", name])
                    done.resume()
                }
            }
            if !isRunning(p.pid, startedBy: scanned) { return }
        }

        let pids = p.tree.filter { $0 > 1 && isRunning($0, startedBy: scanned) }
        pids.forEach { kill($0, force ? SIGKILL : SIGTERM) }
        guard !force else { return }

        for _ in 0..<30 {
            if !pids.contains(where: { isRunning($0, startedBy: scanned) }) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        pids.filter { isRunning($0, startedBy: scanned) }.forEach { kill($0, SIGKILL) }
    }

    /// Alive, not a zombie waiting to be reaped, and started no later than `scanned`.
    private static func isRunning(_ pid: Int32, startedBy scanned: Date) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0,
              Int32(info.kp_proc.p_stat) != SZOMB else { return false }
        let t = info.kp_proc.p_starttime
        return Double(t.tv_sec) + Double(t.tv_usec) / 1e6 <= scanned.timeIntervalSince1970
    }
}
