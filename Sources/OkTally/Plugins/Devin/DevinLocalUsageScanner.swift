// Sources/OkTally/Plugins/Devin/DevinLocalUsageScanner.swift
import Foundation
import GRDB

/// Lê o `sessions.db` local do Devin CLI e extrai somente os metadados numéricos de
/// geração (`metadata.metrics`). Confirmado no banco real em 2026-11-25: cada mensagem
/// gerada carrega `input_tokens`, `output_tokens`, `cache_read_tokens` e
/// `cache_creation_tokens`; `context_input_tokens` é a soma do input não-cacheado com o
/// cache lido, então NÃO entra na soma para não duplicar.
///
/// O JSON da mensagem é decodificado em memória para chegar ao metadata, mas conteúdo de
/// conversa nunca é armazenado, exibido ou persistido pelo OkTally. Como no scanner do
/// Claude, isto é uma exceção local e deliberada à regra de não depender de artefatos de
/// terceiros: sem o Devin instalado não há uso local para medir.
final class DevinLocalUsageScanner {
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/.local/share/devin/cli/sessions.db") {
        self.dbPath = dbPath
    }

    func analytics(windowDays: Int = 365, now: Date = Date()) -> TokenAnalytics? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        var config = Configuration()
        config.readonly = true
        guard let dbQueue = try? DatabaseQueue(path: dbPath, configuration: config) else { return nil }

        let cutoff = Int64(now.addingTimeInterval(-Double(windowDays) * 24 * 3600).timeIntervalSince1970)
        let rows: [Row]? = try? dbQueue.read { db in
            guard try db.tableExists("message_nodes") else { return [] }
            return try Row.fetchAll(
                db,
                sql: "SELECT created_at, chat_message FROM message_nodes WHERE created_at >= ? AND chat_message IS NOT NULL",
                arguments: [cutoff]
            )
        }
        guard let rows else { return nil }

        var byDay: [String: Int] = [:]
        for row in rows {
            guard let createdAt: Int64 = row["created_at"],
                  let messageJSON: String = row["chat_message"],
                  let tokens = Self.tokens(inMessageJSON: messageJSON), tokens > 0 else { continue }
            let day = TokenAnalytics.dayKey(Date(timeIntervalSince1970: TimeInterval(createdAt)))
            byDay[day, default: 0] += tokens
        }
        let buckets = byDay.map { DailyTokens(day: $0.key, tokens: $0.value) }
        guard !buckets.isEmpty else { return nil }
        return TokenAnalytics(dailyBuckets: buckets)
    }

    /// Soma os componentes independentes de input. `cache_creation_tokens` costuma vir
    /// `null` nas versões atuais, mas é somado quando aparece. Números stringados são
    /// aceitos porque o contrato interno não é versionado.
    static func tokens(inMessageJSON string: String) -> Int? {
        guard let data = string.data(using: .utf8),
              let root = TolerantJSON.object(data: data),
              let metadata = TolerantJSON.object(root["metadata"]),
              let metrics = TolerantJSON.object(metadata["metrics"]) else { return nil }
        let input = TolerantJSON.number(in: metrics, camel: "inputTokens") ?? 0
        let output = TolerantJSON.number(in: metrics, camel: "outputTokens") ?? 0
        let cacheRead = TolerantJSON.number(in: metrics, camel: "cacheReadTokens") ?? 0
        let cacheCreation = TolerantJSON.number(in: metrics, camel: "cacheCreationTokens") ?? 0
        let total = input + output + cacheRead + cacheCreation
        return total > 0 ? Int(total.rounded()) : nil
    }
}
