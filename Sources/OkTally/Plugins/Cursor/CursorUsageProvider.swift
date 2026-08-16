// Sources/OkTally/Plugins/Cursor/CursorUsageProvider.swift
import Foundation

final class CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let displayName = "Cursor"
    let authMethod: AuthMethod = .localFile(path: NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    let refreshInterval: TimeInterval = 600

    private let tokenReader: CursorTokenReading
    private let client: CursorUsageFetching

    init(tokenReader: CursorTokenReading = CursorTokenReader(), client: CursorUsageFetching = CursorUsageAPIClient()) {
        self.tokenReader = tokenReader
        self.client = client
    }

    func isAuthenticated() async -> Bool {
        tokenReader.readAccessToken() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let token = tokenReader.readAccessToken() else { throw CursorUsageError.notDetected }
        let response = try await client.fetchUsage(accessToken: token)

        // Included monthly credit pool (e.g. $20 on Pro, $400 on Ultra) minus spend.
        // Prefer `limit - totalSpend` when the API still sends `totalSpend`: it can go
        // negative on overage, which is surfaced as-is rather than clamped, since it's
        // meaningful (usage above the included plan allotment). When Cursor omits
        // `totalSpend` (schema change observed 2026-08-17), fall back to the API's own
        // `remaining` figure. With neither, skip the balance window instead of guessing —
        // the percent window below still reports usage.
        var windows = [QuotaWindow]()
        let remainingCents: Double?
        if let totalSpend = response.planUsage.totalSpend {
            remainingCents = response.planUsage.limit - totalSpend
        } else {
            remainingCents = response.planUsage.remaining
        }
        if let remainingCents {
            let remaining = Decimal(remainingCents) / 100
            windows.append(QuotaWindow(label: "balance", shape: .creditBalance(remaining: remaining, currency: "USD")))
        }
        // The API also hands back a ready-made percent-of-plan figure directly
        // (`totalPercentUsed`) — surface it as its own window so Cursor participates in
        // the menu-bar icon aggregation and percentage-based alerts like every other
        // percent-based provider. `creditBalance` alone never contributes a percent.
        if let resetAt = Self.parseEpochMillis(response.billingCycleEnd) {
            let percentWindow = QuotaWindow(
                label: "percent",
                shape: .periodicCounter(used: response.planUsage.totalPercentUsed, limit: 100, resetAt: resetAt)
            )
            windows.append(percentWindow)
        }

        return ProviderSnapshot(
            providerId: id,
            fetchedAt: Date(),
            quotas: windows,
            usageDetail: nil,
            planLabel: tokenReader.readMembershipType().map(Self.planDisplayName)
        )
    }

    /// "pro" → "Pro", "pro_student" → "Pro Student".
    static func planDisplayName(_ raw: String) -> String {
        raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func parseEpochMillis(_ value: String) -> Date? {
        guard let millis = Double(value) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
