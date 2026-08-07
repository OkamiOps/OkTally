// Sources/OkTally/Core/UsageProvider.swift
import Foundation

enum AuthMethod {
    case keychain(service: String)
    case localFile(path: String)
    case apiKey
    case oauthSession
}

protocol UsageProvider {
    var id: String { get }
    var displayName: String { get }
    var authMethod: AuthMethod { get }
    var refreshInterval: TimeInterval { get }

    func isAuthenticated() async -> Bool
    func fetchSnapshot() async throws -> ProviderSnapshot
}
