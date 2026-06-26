import XCTest
@testable import Claudemon

/// Regression tests for the spawn-environment builder. The `claude` CLI returns
/// a generic EMPTY body (exit 0, no metrics) when `USER` is missing from its
/// environment, which made the app hang on "Waiting for usage data…" forever
/// when launched as a login item (launchd gives a minimal env without USER).
/// `makeEnvironment` must therefore guarantee USER/LOGNAME are present.
final class UsageFetcherEnvTests: XCTestCase {

    private let workingDir = URL(fileURLWithPath: "/tmp/claudemon-env-test", isDirectory: true)

    func testEnvIncludesUserAndLognameWhenBaseLacksThem() {
        // Base env deliberately WITHOUT USER/LOGNAME (mirrors a launchd login item).
        let base = ["PATH": "/usr/bin"]
        let env = UsageFetcher.makeEnvironment(base: base, workingDir: workingDir)

        XCTAssertEqual(env["USER"], NSUserName(),
                       "USER must be set to the current user even when the base env lacks it")
        XCTAssertEqual(env["LOGNAME"], NSUserName(),
                       "LOGNAME must be set to the current user even when the base env lacks it")
        XCTAssertFalse(env["USER"]?.isEmpty ?? true)
        XCTAssertFalse(env["LOGNAME"]?.isEmpty ?? true)
    }

    func testEnvOverridesPreexistingUserWithCurrentUser() {
        // Even if a (stale/wrong) USER is present, normalize to the real user.
        let base = ["USER": "someone-else", "LOGNAME": "someone-else"]
        let env = UsageFetcher.makeEnvironment(base: base, workingDir: workingDir)

        XCTAssertEqual(env["USER"], NSUserName())
        XCTAssertEqual(env["LOGNAME"], NSUserName())
    }

    func testEnvStillNeutralizesWorkingDirAndPath() {
        // The pre-existing PATH/PWD/OLDPWD behaviour must be unchanged.
        let base = ["PATH": "/custom/bin"]
        let env = UsageFetcher.makeEnvironment(base: base, workingDir: workingDir)

        XCTAssertEqual(env["PWD"], workingDir.path)
        XCTAssertEqual(env["OLDPWD"], workingDir.path)
        XCTAssertEqual(env["PATH"],
                       "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/custom/bin",
                       "The homebrew PATH prepend must still wrap the base PATH")
    }
}
