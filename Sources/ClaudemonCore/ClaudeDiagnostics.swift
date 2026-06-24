import Foundation

/// Pure, testable classification of `claude` CLI failures, kept in ClaudemonCore
/// so it can be unit-tested from the `ClaudemonCore`-linked test target.
public enum ClaudeDiagnostics {

    /// Heuristic: does a non-zero exit's stderr look like an AUTH / sign-in
    /// issue (vs a generic error)? Needles are deliberately auth-specific to
    /// avoid false positives — note we do NOT match a bare "login" (which would
    /// also match "logging"); we require "/login" or "log in" etc.
    public static func looksLikeAuthFailure(stderr: String) -> Bool {
        let s = stderr.lowercased()
        let needles = [
            "/login",
            "log in",
            "not logged in",
            "please run",
            "sign in",
            "signin",
            "unauthorized",
            "authentication",
            "authenticate",
            "not authenticated",
            "no subscription",
            "credentials"
        ]
        return needles.contains { s.contains($0) }
    }
}
