// Adapted from portside by guneysol (MIT), https://github.com/guneysol/portside.
// See THIRD_PARTY_LICENSES.

import Foundation

enum Kind: String, Codable {
    case web, database, service, runtime

    var symbol: String {
        switch self {
        case .web: "globe"
        case .database: "cylinder.split.1x2"
        case .service: "shippingbox"
        case .runtime: "terminal"
        }
    }
}

struct ListenPort: Hashable, Comparable, Codable {
    let number: Int
    /// Bound to all interfaces (reachable from the network), not just loopback.
    let exposed: Bool

    static func < (a: ListenPort, b: ListenPort) -> Bool { a.number < b.number }
}

struct Project: Hashable, Codable {
    let root: String
    let name: String
    let branch: String?
    let isWorktree: Bool
}

struct DevProcess: Identifiable, Hashable, Codable {
    let pid: Int32
    var id: Int32 { pid }
    let name: String
    let kind: Kind
    let command: String
    /// Short, human command — e.g. "npm run dev" rather than the node binary path.
    let summary: String
    let exePath: String
    let cwd: String
    var ports: [ListenPort]
    /// A start date rather than an uptime, so unchanged scans compare equal
    /// and SwiftUI has nothing to redraw.
    let started: Date
    let project: Project?
    /// Who started it: "Claude Code", "Cursor", "Terminal", "brew services"…
    let origin: String?
    /// Every pid that goes down when this is stopped (wrapper root + descendants).
    let tree: [Int32]
    let launchdLabel: String?
    let isSystem: Bool
    /// Owned by another user (root…): visible, but we can't stop it.
    let isOwned: Bool
    /// Set for a Docker container's row; Stop goes through the engine (`docker stop`).
    var container: Container? = nil

    /// Docker Desktop, OrbStack… forward every container's ports through one process.
    /// Stopping it would take down every container (or the app), so it never is.
    var isContainerEngine: Bool { Self.containerEngines.contains(where: exePath.contains) }
    static let containerEngines = ["/Docker.app/", "/OrbStack.app/", "/Rancher Desktop.app/", "/Podman Desktop.app/"]

    /// Has a Stop button. Stop All also skips system and app listeners.
    var canStop: Bool { isOwned && !isContainerEngine }

    /// Working directory relative to the project root ("apps/web"), nil at the root itself.
    var subpath: String? {
        guard let root = project?.root, cwd.hasPrefix(root + "/") else { return nil }
        return String(cwd.dropFirst(root.count + 1))
    }
}

/// A running container behind a published port. Read from the engine's local unix socket
/// (the same API `docker ps` uses), so the docker CLI doesn't need to be installed or on PATH.
struct Container: Hashable, Codable {
    let id: String
    let name: String
    let image: String
    let command: String
    let created: Date
    let ports: [ListenPort]
    let composeProject: String?
    let composeService: String?
    let composeDirectory: String?
    let socket: String
}

/// What the app sends the helper to stop: rows from one scan, and when that scan started.
struct StopRequest: Codable {
    let processes: [DevProcess]
    let asOf: Date
}

struct ProcessGroup: Identifiable {
    let id: String
    let project: Project?
    let processes: [DevProcess]

    var title: String { project?.name ?? "Services" }
}

enum Format {
    static func uptime(_ t: TimeInterval) -> String {
        let s = Int(t)
        switch s {
        case ..<60: return "<1m"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h \(s % 3600 / 60)m"
        default: return "\(s / 86400)d \(s % 86400 / 3600)h"
        }
    }

    static func abbreviatingHome(_ path: String) -> String {
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// The real home, also in the sandboxed app, where NSHomeDirectory() is the app's container.
    static let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
}

extension StringProtocol {
    /// "/usr/bin/node" → "node". Avoids bridging to NSString: this runs for
    /// every command-line token on every scan.
    var basename: SubSequence {
        var end = endIndex
        while end > startIndex, self[index(before: end)] == "/" { end = index(before: end) }
        let start = self[..<end].lastIndex(of: "/").map(index(after:)) ?? startIndex
        return self[start..<end]
    }
}
