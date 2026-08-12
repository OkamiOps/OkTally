// Sources/OkTally/Plugins/Copilot/CopilotTokenReader.swift
import Foundation

/// Zero-config credential discovery for GitHub Copilot, mirroring the Cursor plugin's
/// "read what the tool already left on disk" approach (and Quotio's Copilot fetcher):
/// the Copilot IDE plugins persist an OAuth token in `~/.config/github-copilot/`
/// (`apps.json` / `hosts.json`), and the `gh` CLI keeps one in `~/.config/gh/hosts.yml`.
/// Any of them works against `api.github.com/copilot_internal/user`. Read-only, never
/// throws — a missing/binary/garbled file just means "not detected".
protocol CopilotTokenReading {
    func firstToken() -> String?
}

final class CopilotTokenReader: CopilotTokenReading {
    private let homeDirectory: String

    init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    func firstToken() -> String? {
        // Copilot's own files first: they're guaranteed to be Copilot-scoped tokens,
        // while a gh CLI token might lack the Copilot entitlement scope.
        for file in ["apps.json", "hosts.json"] {
            let path = homeDirectory + "/.config/github-copilot/" + file
            if let token = firstJSONToken(atPath: path) { return token }
        }
        return ghCLIToken()
    }

    /// Both Copilot files are dictionaries keyed by host/app whose values carry an
    /// `oauth_token` — but the exact nesting has changed across plugin versions, so
    /// collect recursively instead of pinning a shape.
    private func firstJSONToken(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return collectToken(from: object)
    }

    private func collectToken(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if ["oauth_token", "oauthToken", "access_token"].contains(key),
                   let token = child as? String, !token.isEmpty {
                    return token
                }
                if let nested = collectToken(from: child) { return nested }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let nested = collectToken(from: child) { return nested }
            }
        }
        return nil
    }

    /// `hosts.yml` is YAML, but the one line we need is flat (`  oauth_token: gho_…`), so
    /// a line scan avoids a YAML dependency.
    private func ghCLIToken() -> String? {
        let path = homeDirectory + "/.config/gh/hosts.yml"
        guard let yaml = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in yaml.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "oauth_token" else { continue }
            let token = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        return nil
    }
}
