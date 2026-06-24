import Foundation

/// Pure, testable discovery of the `claude` executable across the common
/// install layouts (Homebrew, official local installer, npm-global, pnpm,
/// volta, asdf, and the nvm/fnm per-version dirs). This does NOT spawn any
/// process — the login-shell fallback lives in the app's `UsageFetcher`. Kept
/// in ClaudemonCore so it can be unit-tested without the app target.
public struct ClaudeLocator {

    private let fileManager: FileManager
    private let homeDirectory: String
    /// Absolute (non-home) system locations. Injectable so tests can isolate
    /// from whatever is installed on the host machine.
    private let systemPaths: [String]

    /// The real system locations checked in production.
    public static let defaultSystemPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude"
    ]

    public init(fileManager: FileManager = .default,
                homeDirectory: String? = nil,
                systemPaths: [String] = ClaudeLocator.defaultSystemPaths) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
            ?? fileManager.homeDirectoryForCurrentUser.path
        self.systemPaths = systemPaths
    }

    /// Concrete (non-glob) candidate locations in priority order.
    public var candidatePaths: [String] {
        systemPaths + [
            "\(homeDirectory)/.claude/local/claude",
            "\(homeDirectory)/.local/bin/claude",
            "\(homeDirectory)/.npm-global/bin/claude",
            "\(homeDirectory)/Library/pnpm/claude",
            "\(homeDirectory)/.volta/bin/claude",
            "\(homeDirectory)/.asdf/shims/claude"
        ]
    }

    /// Glob roots for version managers that nest binaries per node version.
    public var globRoots: [String] {
        [
            "\(homeDirectory)/.nvm/versions/node",
            "\(homeDirectory)/.fnm"
        ]
    }

    /// Resolve via concrete candidates first, then version-manager globs.
    /// Returns nil if not found by these filesystem checks (the app then tries
    /// the login-shell fallback).
    public func locateFromFilesystem() -> String? {
        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return firstClaudeUnderGlobRoots()
    }

    /// Search the glob roots for an executable named `claude`.
    public func firstClaudeUnderGlobRoots() -> String? {
        for root in globRoots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard fileManager.fileExists(atPath: root),
                  let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if url.lastPathComponent == "claude",
                   fileManager.isExecutableFile(atPath: url.path) {
                    return url.path
                }
            }
        }
        return nil
    }
}
