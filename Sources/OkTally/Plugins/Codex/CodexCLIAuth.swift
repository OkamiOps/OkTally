// Sources/OkTally/Plugins/Codex/CodexCLIAuth.swift
import Foundation

/// Read-only view of the Codex CLI login at `~/.codex/auth.json`.
///
/// OkTally keeps its own OAuth session so a second Codex account does not have to follow
/// whatever the CLI is signed into. When that private session can no longer read usage,
/// the CLI session for the *same* ChatGPT account is still a valid read-only credential.
/// The refresh token stays in the file: presenting it to the token endpoint would rotate
/// it and sign the CLI out.
struct CodexCLICredentials: Equatable {
    let accessToken: String
    let accountId: String?
    let email: String?
}

enum CodexCLIAuth {
    static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex/auth.json")
    }

    static func load(from url: URL = defaultURL) -> CodexCLICredentials? {
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty
        else { return nil }
        let accountId = (tokens["account_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let email = (tokens["id_token"] as? String).flatMap(Self.email(fromIdToken:))
        return CodexCLICredentials(accessToken: accessToken, accountId: accountId, email: email)
    }

    /// True only when this CLI login is the same ChatGPT account OkTally stored.
    /// A different email or workspace must not inherit the other account's quota.
    static func matches(_ cli: CodexCLICredentials, accountId: String?, email: String?) -> Bool {
        if let accountId, let cliAccountId = cli.accountId,
           !accountId.isEmpty, accountId == cliAccountId {
            return true
        }
        if let email, let cliEmail = cli.email,
           !email.isEmpty, sameAddress(email, cliEmail) {
            return true
        }
        return false
    }

    static func accountId(from accessToken: String?) -> String? {
        guard let accessToken,
              let auth = JWT.decodePayload(accessToken)?["https://api.openai.com/auth"] as? [String: Any],
              let accountId = auth["chatgpt_account_id"] as? String,
              !accountId.isEmpty
        else { return nil }
        return accountId
    }

    private static func email(fromIdToken idToken: String) -> String? {
        guard let payload = JWT.decodePayload(idToken) else { return nil }
        if let email = payload["email"] as? String, !email.isEmpty { return email }
        let profile = payload["https://api.openai.com/profile"] as? [String: Any]
        if let email = profile?["email"] as? String, !email.isEmpty { return email }
        return nil
    }

    private static func sameAddress(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
