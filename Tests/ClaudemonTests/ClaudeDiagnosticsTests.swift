import XCTest
@testable import ClaudemonCore

/// Tests for the pure auth-failure stderr classifier. These guard against
/// false positives (a generic error misread as "Sign in") for the npm/nvm
/// friend audience.
final class ClaudeDiagnosticsTests: XCTestCase {

    // MARK: - Should classify as auth failure (true)

    func testInvalidApiKeyPleaseRunLoginIsAuth() {
        XCTAssertTrue(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "Invalid API key · please run /login"))
    }

    func testNotLoggedInIsAuth() {
        XCTAssertTrue(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "Error: you are not logged in"))
    }

    func testUnauthorizedIsAuth() {
        XCTAssertTrue(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "401 Unauthorized"))
    }

    func testAuthenticationRequiredIsAuth() {
        XCTAssertTrue(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "Authentication required"))
    }

    func testPleaseLogInIsAuth() {
        XCTAssertTrue(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "Please log in to continue"))
    }

    func testNoSubscriptionIsAuth() {
        XCTAssertTrue(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "No subscription found for this account"))
    }

    // MARK: - Should NOT classify as auth failure (false)

    func testNetworkErrorIsNotAuth() {
        XCTAssertFalse(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "network error: connection reset"))
    }

    func testLoggingOutputIsNotAuth() {
        // The whole point of dropping the bare "login" needle: "logging" must
        // NOT match.
        XCTAssertFalse(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "logging output enabled"))
    }

    func testGenericRuntimeErrorIsNotAuth() {
        XCTAssertFalse(ClaudeDiagnostics.looksLikeAuthFailure(
            stderr: "TypeError: cannot read property of undefined"))
    }

    func testEmptyStderrIsNotAuth() {
        XCTAssertFalse(ClaudeDiagnostics.looksLikeAuthFailure(stderr: ""))
    }
}
