// Sources/OkTally/App/ProviderErrorPresentation.swift
import Foundation

/// How a provider card should visually present a fetch failure. Collapsing every failure
/// into the same red text reads as "the app is broken" on first launch, when all 8
/// providers are legitimately just unconfigured. Distinguishing these lets the UI reserve
/// red for things that actually need attention.
enum ProviderErrorPresentation: Equatable {
    /// The owner hasn't set anything up yet for this provider (no API key entered, no
    /// OAuth login performed, no local install detected). Expected, common, not alarming.
    case notConfigured
    /// The provider WAS working but the stored credentials no longer are (refresh token
    /// missing/rejected, device-code flow denied/expired). Needs the owner to log in
    /// again, but isn't a crash or a network problem.
    case needsReauth
    /// Something unexpected happened (bad HTTP status, malformed response, timeout, …).
    case error

    /// Classifies a fetch failure using the error's concrete type — every provider
    /// already throws a typed, `LocalizedError`-conforming error, so we don't need to
    /// pattern-match message strings.
    static func classify(_ error: Error) -> ProviderErrorPresentation {
        if let error = error as? SchedulerError {
            switch error {
            case .notConfigured: return .notConfigured
            }
        }
        if let error = error as? OAuthError {
            switch error {
            case .noRefreshToken, .refreshFailed:
                return .needsReauth
            case .tokenExchangeFailed, .loginTimeout, .portInUse:
                return .error
            }
        }
        if let error = error as? DeviceCodeError {
            switch error {
            case .accessDenied, .expired:
                return .needsReauth
            case .requestFailed, .invalidResponse:
                return .error
            }
        }
        if let error = error as? OpenRouterError, error == .missingAPIKey { return .notConfigured }
        if let error = error as? MiniMaxError, error == .missingAPIKey { return .notConfigured }
        if let error = error as? CursorUsageError, error == .notDetected { return .notConfigured }
        if let error = error as? OpenCodeError, error == .notDetected { return .notConfigured }
        return .error
    }
}
