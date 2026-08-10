// Sources/OkTally/Plugins/MiMo/MiMoSessionRecovery.swift
import Foundation

/// The STS cookie behind the MiMo console expires long before the Xiaomi SSO session
/// does. A 401 therefore usually means "stale STS", not "logged out" — reloading the
/// console page re-runs the SSO redirect chain and mints a fresh STS. Only a 401 that
/// survives that reload means the SSO itself is dead and the user must log in again.
struct MiMoSessionRecovery {
    private let fetch: () async throws -> Data
    private let reload: () async throws -> Void

    init(fetch: @escaping () async throws -> Data, reload: @escaping () async throws -> Void) {
        self.fetch = fetch
        self.reload = reload
    }

    func fetchWithRecovery() async throws -> Data {
        let first = try await fetch()
        guard isUnauthorized(first) else { return first }
        try await reload()
        let second = try await fetch()
        guard isUnauthorized(second) else { return second }
        throw MiMoConsoleError.notLoggedIn
    }

    private func isUnauthorized(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.contains("\"code\":401") ?? false
    }
}
