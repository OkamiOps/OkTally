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

        // Included monthly credit pool (e.g. $20 on Pro), minus total spend drawn from it
        // plus any bonus credits Cursor granted. Can go negative once bonus credits are
        // consumed too — that's surfaced as-is rather than clamped, since it's meaningful
        // (usage above the included plan allotment).
        let remainingCents = response.planUsage.limit - response.planUsage.totalSpend
        let remaining = Decimal(remainingCents) / 100
        let balanceWindow = QuotaWindow(label: "balance", shape: .creditBalance(remaining: remaining, currency: "USD"))

        var windows = [balanceWindow]
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

        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: windows, usageDetail: nil)
    }

    private static func parseEpochMillis(_ value: String) -> Date? {
        guard let millis = Double(value) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
