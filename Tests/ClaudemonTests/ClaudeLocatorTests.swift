import XCTest
@testable import ClaudemonCore

/// Tests for the process-free `claude` discovery used by the friend-failure fix.
final class ClaudeLocatorTests: XCTestCase {

    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudemon-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome { try? FileManager.default.removeItem(at: tempHome) }
    }

    /// Create an executable stub at the given relative path under the fake home.
    @discardableResult
    private func makeExecutable(at relativePath: String) throws -> String {
        let url = tempHome.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho hi\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func testFindsClaudeInNpmGlobalBin() throws {
        let expected = try makeExecutable(at: ".npm-global/bin/claude")
        let locator = ClaudeLocator(homeDirectory: tempHome.path, systemPaths: [])
        XCTAssertEqual(locator.locateFromFilesystem(), expected)
    }

    func testFindsClaudeInPnpmDir() throws {
        let expected = try makeExecutable(at: "Library/pnpm/claude")
        let locator = ClaudeLocator(homeDirectory: tempHome.path, systemPaths: [])
        XCTAssertEqual(locator.locateFromFilesystem(), expected)
    }

    /// Compare paths by their resolved (symlink-canonical) form so /var vs
    /// /private/var temp-dir differences don't cause spurious failures.
    private func assertSamePath(_ a: String?, _ b: String, file: StaticString = #filePath, line: UInt = #line) {
        let ra = a.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        let rb = URL(fileURLWithPath: b).resolvingSymlinksInPath().path
        XCTAssertEqual(ra, rb, file: file, line: line)
    }

    func testFindsClaudeUnderNvmVersionGlob() throws {
        // nvm layout: ~/.nvm/versions/node/<version>/bin/claude
        let expected = try makeExecutable(at: ".nvm/versions/node/v22.3.0/bin/claude")
        let locator = ClaudeLocator(homeDirectory: tempHome.path, systemPaths: [])
        assertSamePath(locator.firstClaudeUnderGlobRoots(), expected)
        assertSamePath(locator.locateFromFilesystem(), expected)
    }

    func testFindsClaudeUnderFnmNestedDir() throws {
        // fnm nests node installs a few levels deep.
        let expected = try makeExecutable(at: ".fnm/node-versions/v20.11.1/installation/bin/claude")
        let locator = ClaudeLocator(homeDirectory: tempHome.path, systemPaths: [])
        assertSamePath(locator.firstClaudeUnderGlobRoots(), expected)
    }

    func testReturnsNilWhenClaudeMissingEverywhere() throws {
        // Empty fake home, no claude anywhere the locator looks.
        let locator = ClaudeLocator(homeDirectory: tempHome.path, systemPaths: [])
        XCTAssertNil(locator.locateFromFilesystem(),
                     "A totally-missing claude must not be located from the filesystem")
    }

    func testIgnoresNonExecutableNamedClaude() throws {
        // A plain (non-executable) file named claude should NOT match.
        let url = tempHome.appendingPathComponent(".npm-global/bin/claude")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not executable".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        let locator = ClaudeLocator(homeDirectory: tempHome.path, systemPaths: [])
        XCTAssertNil(locator.locateFromFilesystem())
    }
}
