// Sources/OkTally/Plugins/Claude/ClaudeLocalUsageScanner.swift
import Foundation

/// Constrói o `TokenAnalytics` do Claude a partir dos transcritos locais do Claude Code
/// (`~/.claude/projects/**/*.jsonl`) — a mesma fonte que ferramentas como ccusage leem.
/// Cada linha "assistant" carrega `message.usage` com contagens de tokens; somamos
/// input + output + cache (criação e leitura) por dia local.
///
/// O corpus pode passar de centenas de MB, então há um cache incremental por arquivo
/// (mtime+size → totais por dia) persistido em Application Support: só arquivos novos ou
/// alterados são re-parseados. Deduplicação por `message.id`+`requestId` é feita DENTRO
/// de cada arquivo; mensagens repetidas entre arquivos (sessões retomadas com --resume)
/// podem contar duas vezes — limitação aceita e documentada, é uma estimativa local.
final class ClaudeLocalUsageScanner {
    struct FileDigest: Codable, Equatable {
        let mtime: Double
        let size: Int64
        let days: [String: Int]
    }

    private let projectsDir: String
    private let cachePath: String?
    private var cache: [String: FileDigest] = [:]
    private var cacheLoaded = false

    init(
        projectsDir: String = NSHomeDirectory() + "/.claude/projects",
        cachePath: String? = NSHomeDirectory() + "/Library/Application Support/OkTally/claude-usage-cache.json"
    ) {
        self.projectsDir = projectsDir
        self.cachePath = cachePath
    }

    /// Varre o corpus e devolve os baldes diários dos últimos `windowDays`. `nil` quando
    /// o diretório não existe (Claude Code não instalado). Nunca lança.
    func analytics(windowDays: Int = 365, now: Date = Date()) -> TokenAnalytics? {
        guard FileManager.default.fileExists(atPath: projectsDir) else { return nil }
        loadCacheIfNeeded()

        let files = jsonlFiles()
        guard !files.isEmpty else { return nil }

        var mergedDays: [String: Int] = [:]
        var newCache: [String: FileDigest] = [:]
        var cacheChanged = false

        for file in files {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file),
                  let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate,
                  let size = (attributes[.size] as? NSNumber)?.int64Value
            else { continue }

            let digest: FileDigest
            if let cached = cache[file], cached.mtime == mtime, cached.size == size {
                digest = cached
            } else {
                digest = FileDigest(mtime: mtime, size: size, days: Self.parseFile(atPath: file))
                cacheChanged = true
            }
            newCache[file] = digest
            for (day, tokens) in digest.days {
                mergedDays[day, default: 0] += tokens
            }
        }

        if cacheChanged || newCache.keys != cache.keys {
            cache = newCache
            saveCache()
        }

        let cutoff = TokenAnalytics.dayKey(now.addingTimeInterval(-Double(windowDays) * 24 * 3600))
        let buckets = mergedDays
            .filter { $0.key >= cutoff }
            .map { DailyTokens(day: $0.key, tokens: $0.value) }
        guard !buckets.isEmpty else { return nil }
        return TokenAnalytics(dailyBuckets: buckets)
    }

    // MARK: - Parsing de um arquivo

    /// Totais por dia de um único .jsonl. Estático e puro (fora o I/O) para ser testável.
    static func parseFile(atPath path: String) -> [String: Int] {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return [:] }

        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        var days: [String: Int] = [:]
        var seen = Set<String>()

        for line in content.split(separator: "\n") {
            // Filtro barato antes do JSON: só linhas de assistant com usage interessam.
            guard line.contains("\"usage\""), line.contains("\"assistant\"") else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestampRaw = object["timestamp"] as? String,
                  let timestamp = isoWithFraction.date(from: timestampRaw) ?? iso.date(from: timestampRaw)
            else { continue }

            // Streaming grava a mesma mensagem em várias linhas conforme os blocos
            // chegam — o usage é cumulativo, então só a combinação id+requestId única
            // pode contar.
            let messageId = message["id"] as? String ?? ""
            let requestId = object["requestId"] as? String ?? ""
            if !messageId.isEmpty || !requestId.isEmpty {
                guard seen.insert("\(messageId)#\(requestId)").inserted else { continue }
            }

            let tokens = intValue(usage["input_tokens"]) + intValue(usage["output_tokens"])
                + intValue(usage["cache_creation_input_tokens"]) + intValue(usage["cache_read_input_tokens"])
            guard tokens > 0 else { continue }
            days[TokenAnalytics.dayKey(timestamp), default: 0] += tokens
        }
        return days
    }

    private static func intValue(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? 0
    }

    // MARK: - Arquivos e cache

    private func jsonlFiles() -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: projectsDir) else { return [] }
        var files: [String] = []
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix(".jsonl") else { continue }
            files.append(projectsDir + "/" + relative)
        }
        return files.sorted()
    }

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let cachePath,
              let data = FileManager.default.contents(atPath: cachePath),
              let decoded = try? JSONDecoder().decode([String: FileDigest].self, from: data)
        else { return }
        cache = decoded
    }

    private func saveCache() {
        guard let cachePath, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
    }
}
