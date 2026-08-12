// Sources/OkTally/Core/UpdateChecker.swift
import Foundation

/// Verificação de atualização contra as releases do GitHub — deliberadamente no lugar de
/// Sparkle: sem notarização, a instalação automática esbarraria no Gatekeeper de
/// qualquer forma, então o honesto é avisar e levar o dono à página da release.
/// Roda uma vez por dia; falha de rede é silenciosa (tenta de novo no próximo ciclo).
struct UpdateInfo: Equatable {
    let version: String
    let url: URL
}

protocol LatestReleaseFetching {
    /// Devolve (tag, htmlURL) da release mais recente (inclui prereleases), ou nil.
    func fetchLatestRelease() async throws -> (tag: String, url: URL)?
}

final class GitHubLatestReleaseFetcher: LatestReleaseFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchLatestRelease() async throws -> (tag: String, url: URL)? {
        // `releases?per_page=1` em vez de `releases/latest` porque o endpoint "latest"
        // ignora prereleases — e hoje todas as versões são beta.
        let url = URL(string: "https://api.github.com/repos/OkamiOps/OkTally/releases?per_page=1")!
        var request = URLRequest(url: url)
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let tag = first["tag_name"] as? String,
              let htmlURL = (first["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        return (tag, htmlURL)
    }
}

enum UpdateChecker {
    /// Compara versões "x.y.z" numericamente, ignorando prefixo "v" e sufixos como
    /// "-beta" (0.9.0-beta == 0.9.0 — betas da mesma versão não geram aviso).
    static func isNewer(remoteTag: String, than currentVersion: String) -> Bool {
        let remote = numericParts(remoteTag)
        let current = numericParts(currentVersion)
        guard !remote.isEmpty, !current.isEmpty else { return false }
        let count = max(remote.count, current.count)
        for index in 0..<count {
            let r = index < remote.count ? remote[index] : 0
            let c = index < current.count ? current[index] : 0
            if r != c { return r > c }
        }
        return false
    }

    static func numericParts(_ raw: String) -> [Int] {
        var value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        if let dash = value.firstIndex(of: "-") { value = String(value[..<dash]) }
        let parts = value.split(separator: ".").map(String.init)
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : []
    }

    /// Info de atualização quando a release remota é mais nova que a versão instalada.
    static func availableUpdate(
        remote: (tag: String, url: URL)?,
        currentVersion: String
    ) -> UpdateInfo? {
        guard let remote, isNewer(remoteTag: remote.tag, than: currentVersion) else { return nil }
        return UpdateInfo(version: remote.tag, url: remote.url)
    }
}
