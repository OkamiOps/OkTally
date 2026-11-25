import Foundation

enum DevinError: Error, Equatable {
    case notDetected
    case tokenRejected
    case badResponse(Int)
}

extension DevinError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDetected:
            return L("Devin não detectado — instale/entre no Devin CLI para acompanhar o uso.")
        case .tokenRejected:
            return L("Login do Devin recusado — execute o login do Devin CLI novamente.")
        case .badResponse(let status):
            return LF("Devin respondeu HTTP %d.", status)
        }
    }
}

struct DevinCredentials: Equatable {
    let apiKey: String
    let serverURL: URL
}

protocol DevinCredentialReading {
    func readCredentials() -> DevinCredentials?
}

/// Lê `~/.local/share/devin/credentials.toml`, o arquivo mantido pelo próprio Devin CLI.
/// Parser propositalmente pequeno: o arquivo é um TOML plano de strings (`key = "value"`).
final class DevinCredentialReader: DevinCredentialReading {
    private let path: String

    init(path: String = NSHomeDirectory() + "/.local/share/devin/credentials.toml") {
        self.path = path
    }

    func readCredentials() -> DevinCredentials? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("[") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let raw = parts[1]
            let value: String
            if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
                value = String(raw.dropFirst().dropLast())
            } else {
                value = raw
            }
            values[parts[0]] = value
        }
        guard let key = values["windsurf_api_key"], !key.isEmpty else { return nil }
        let server = values["api_server_url"].flatMap(URL.init(string:)) ?? URL(string: "https://server.codeium.com")!
        return DevinCredentials(apiKey: key, serverURL: server)
    }
}

/// Quota do Devin pelo RPC interno `SeatManagementService/GetUserStatus` — o mesmo
/// contrato consumido pelo CLI. Os percentuais da API são RESTANTES; OkTally guarda uso.
final class DevinUsageProvider: UsageProvider {
    let id: String
    let displayName = "Devin"
    let authMethod: AuthMethod = .localFile(path: "~/.local/share/devin/credentials.toml")
    let refreshInterval: TimeInterval = 600

    private let credentialReader: DevinCredentialReading
    private let session: URLSession

    init(
        instanceId: String = AccountKind.devin.rawValue,
        credentialReader: DevinCredentialReading = DevinCredentialReader(),
        session: URLSession = .shared
    ) {
        self.id = instanceId
        self.credentialReader = credentialReader
        self.session = session
    }

    func isAuthenticated() async -> Bool {
        credentialReader.readCredentials() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let credentials = credentialReader.readCredentials() else { throw DevinError.notDetected }
        let url = credentials.serverURL.appendingPathComponent("exa.seat_management_pb.SeatManagementService/GetUserStatus")
        let body: [String: Any] = [
            "metadata": [
                "apiKey": credentials.apiKey,
                "ideName": "devin",
                "ideVersion": "1.108.2",
                "extensionName": "devin",
                "extensionVersion": "1.108.2",
                "locale": "en"
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DevinError.badResponse(0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw DevinError.tokenRejected }
        guard (200...299).contains(http.statusCode) else { throw DevinError.badResponse(http.statusCode) }
        guard let mapped = Self.snapshotData(from: data) else { throw ProviderAPIError.malformedResponse("Devin") }

        let now = Date()
        var windows: [QuotaWindow] = []
        if let weekly = mapped.weekly {
            windows.append(QuotaWindow(
                label: "weekly",
                shape: .periodicCounter(used: weekly.used, limit: 100, resetAt: weekly.resetAt ?? now.addingTimeInterval(7 * 24 * 3600)),
                renewalCadence: .weekly
            ))
        }
        if let daily = mapped.daily, mapped.hideDailyQuota != true {
            windows.append(QuotaWindow(
                label: "daily",
                shape: .periodicCounter(used: daily.used, limit: 100, resetAt: daily.resetAt ?? now.addingTimeInterval(24 * 3600))
            ))
        }
        guard !windows.isEmpty else { throw ProviderAPIError.malformedResponse("Devin") }
        return ProviderSnapshot(providerId: id, fetchedAt: now, quotas: windows, usageDetail: nil, planLabel: mapped.planName)
    }

    struct SnapshotData: Equatable {
        struct Window: Equatable {
            let used: Double
            let resetAt: Date?
        }
        let weekly: Window?
        let daily: Window?
        let hideDailyQuota: Bool?
        let planName: String?
        let email: String?
    }

    /// Parse tolerante do Connect JSON. Nem todos os planos expõem a cota diária, e a
    /// codificação protobuf frequentemente emite inteiros como strings.
    static func snapshotData(from data: Data) -> SnapshotData? {
        guard let root = TolerantJSON.object(data: data),
              let userStatus = TolerantJSON.object(root["userStatus"]) ?? TolerantJSON.object(TolerantJSON.deepValue(for: "userStatus", in: root)),
              let planStatus = TolerantJSON.object(userStatus["planStatus"]) ?? TolerantJSON.object(TolerantJSON.deepValue(for: "planStatus", in: root)) else { return nil }

        func window(remainingKey: String, resetKey: String) -> SnapshotData.Window? {
            guard let remaining = TolerantJSON.number(in: planStatus, camel: remainingKey) else { return nil }
            let used = min(100, max(0, 100 - remaining))
            let reset = TolerantJSON.unixDate(TolerantJSON.value(in: planStatus, camel: resetKey))
                ?? TolerantJSON.isoDate(TolerantJSON.value(in: planStatus, camel: resetKey))
            return SnapshotData.Window(used: used, resetAt: reset)
        }

        let weekly = window(remainingKey: "weeklyQuotaRemainingPercent", resetKey: "weeklyQuotaResetAtUnix")
        let daily = window(remainingKey: "dailyQuotaRemainingPercent", resetKey: "dailyQuotaResetAtUnix")
        guard weekly != nil || daily != nil else { return nil }
        let planInfo = TolerantJSON.object(planStatus["planInfo"])
        return SnapshotData(
            weekly: weekly,
            daily: daily,
            hideDailyQuota: TolerantJSON.bool(TolerantJSON.value(in: planInfo ?? [:], camel: "hideDailyQuota")),
            planName: planInfo.flatMap { TolerantJSON.string(in: $0, camel: "planName") },
            email: TolerantJSON.string(in: userStatus, camel: "email")
        )
    }
}
