import Foundation

struct OAuthToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let extra: [String: String]

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(60) >= expiresAt
    }
}
