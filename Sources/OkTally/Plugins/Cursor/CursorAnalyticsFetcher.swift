// Sources/OkTally/Plugins/Cursor/CursorAnalyticsFetcher.swift
import Foundation

/// Analytics reais do Cursor pelos endpoints internos de dashboard. O contrato foi
/// descoberto no bundle do Cursor e confirmado ao vivo em 2026-11-25:
/// `GetDailySpendByCategory` devolve tokens por dia/categoria e
/// `GetAggregatedUsageEvents` devolve custo em centavos por modelo no ciclo atual.
///
/// Como são APIs internas, o parsing é deliberadamente tolerante e os dois resultados são
/// independentes: se o custo falhar, tokens ainda aparecem; se tokens falharem, custo ainda
/// aparece. Nada aqui deve derrubar a coleta principal de quota.
final class CursorAnalyticsFetcher {
    static let billingCycleURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetMonthlyBillingCycle")!
    static let aggregatedURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents")!
    static let dailyURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetDailySpendByCategory")!

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetch(accessToken: String, now: Date = Date(), windowDays: Int = 365) async -> TokenAnalytics? {
        // O dashboard do próprio Cursor primeiro resolve o ciclo mensal e só então passa
        // `startDate`/`endDate` ao agregado. Fazer o mesmo evita depender do default do
        // servidor; se o endpoint do ciclo falhar, a chamada sem datas continua como fallback.
        async let billingData = post(Self.billingCycleURL, body: [:], accessToken: accessToken)
        let endMs = Int64(now.timeIntervalSince1970 * 1000)
        // A API detalhada é inconsistente para janelas longas (validado ao vivo: 30–35
        // dias respondem 200; faixas maiores alternam 500 conforme os dados). Usar a
        // janela útil recente evita fingir histórico anual que o endpoint não sustenta.
        let detailedWindowDays = min(windowDays, 35)
        let startMs = Int64(now.addingTimeInterval(-Double(detailedWindowDays) * 24 * 3600).timeIntervalSince1970 * 1000)
        let billing = try? await billingData
        let aggregateBody: [String: Any]
        if let billing, let window = Self.billingWindowMs(data: billing) {
            aggregateBody = ["startDate": String(window.start), "endDate": String(window.end)]
        } else {
            aggregateBody = [:]
        }
        async let aggregatedData = post(Self.aggregatedURL, body: aggregateBody, accessToken: accessToken)
        async let dailyData = fetchDaily(accessToken: accessToken, startMs: startMs, endMs: endMs)

        let aggregated = try? await aggregatedData
        let daily = await dailyData
        return Self.analytics(aggregatedData: aggregated, dailyData: daily)
    }

    /// O endpoint é ocasionalmente instável mesmo dentro da janela suportada. Uma única
    /// segunda tentativa com janela de 30 dias captura a maioria dos casos sem transformar
    /// a aba em um scanner pesado de histórico que a API não oferece.
    private func fetchDaily(accessToken: String, startMs: Int64, endMs: Int64) async -> Data? {
        if let data = try? await post(
            Self.dailyURL,
            body: ["periodStartMs": String(startMs), "periodEndMs": String(endMs)],
            accessToken: accessToken
        ) { return data }

        let fallbackStart = max(startMs, endMs - Int64(30 * 24 * 3600 * 1000))
        guard fallbackStart != startMs else { return nil }
        return try? await post(
            Self.dailyURL,
            body: ["periodStartMs": String(fallbackStart), "periodEndMs": String(endMs)],
            accessToken: accessToken
        )
    }

    private func post(_ url: URL, body: [String: Any], accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CursorUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return data
    }


    static func billingWindowMs(data: Data) -> (start: Int64, end: Int64)? {
        guard let root = TolerantJSON.object(data: data),
              let start = TolerantJSON.number(in: root, camel: "startDateEpochMillis"),
              let end = TolerantJSON.number(in: root, camel: "endDateEpochMillis"),
              end > start else { return nil }
        return (Int64(start), Int64(end))
    }

    /// Parser puro e testável. Tokens diários são a soma de todas as categorias; o custo
    /// vem do ciclo de billing porque o endpoint diário confirmado ao vivo expõe tokens,
    /// mas não `spendCents` para esta conta.
    static func analytics(aggregatedData: Data?, dailyData: Data?) -> TokenAnalytics? {
        analytics(aggregatedData: aggregatedData, dailyDataList: dailyData.map { [$0] } ?? [])
    }

    static func analytics(aggregatedData: Data?, dailyDataList: [Data]) -> TokenAnalytics? {
        var bucketsByDay: [String: Int] = [:]
        for dailyData in dailyDataList {
            guard let root = TolerantJSON.object(data: dailyData),
                  let rows = TolerantJSON.array(TolerantJSON.value(in: root, camel: "dailySpend")) else { continue }
            for row in rows {
                guard let dayMs = TolerantJSON.number(in: row, camel: "day"),
                      let tokens = TolerantJSON.number(in: row, camel: "totalTokens"), tokens > 0 else { continue }
                let day = TokenAnalytics.dayKey(Date(timeIntervalSince1970: dayMs / 1000))
                bucketsByDay[day, default: 0] += Int(tokens.rounded())
            }
        }

        var cost: AnalyticsCostSummary?
        if let aggregatedData, let root = TolerantJSON.object(data: aggregatedData),
           let cents = TolerantJSON.number(in: root, camel: "totalCostCents"), cents > 0 {
            cost = AnalyticsCostSummary(
                amountUSD: Decimal(cents) / 100,
                kind: .metered,
                period: .billingCycle
            )
        }

        let buckets = bucketsByDay.map { DailyTokens(day: $0.key, tokens: $0.value) }
        guard !buckets.isEmpty || cost != nil else { return nil }
        return TokenAnalytics(cost: cost, dailyBuckets: buckets)
    }
}
