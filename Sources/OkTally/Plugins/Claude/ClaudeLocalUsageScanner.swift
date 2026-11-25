// Sources/OkTally/Plugins/Claude/ClaudeLocalUsageScanner.swift
import Foundation

/// Constrói o `TokenAnalytics` do Claude a partir dos transcritos locais do Claude Code
/// (`~/.claude/projects/**/*.jsonl`) — a mesma fonte que ferramentas como ccusage leem.
/// Cada linha "assistant" carrega `message.usage` com contagens de tokens; somamos
/// input + output + cache (criação e leitura) por dia local e preservamos o breakdown por
/// modelo para custo equivalente de API.
///
/// O corpus pode passar de centenas de MB, então há um cache incremental por arquivo
/// (mtime+size → totais por dia/modelo) persistido em Application Support: só arquivos
/// novos ou alterados são re-parseados. Deduplicação por `message.id`+`requestId` é feita
/// DENTRO de cada arquivo; mensagens repetidas entre arquivos (sessões retomadas com
/// --resume) podem contar duas vezes — limitação aceita e documentada.
final class ClaudeLocalUsageScanner {
    struct ModelTokenBreakdown: Codable, Equatable {
        var inputTokens: Int
        var outputTokens: Int
        var cacheReadTokens: Int
        var cacheWriteTokens: Int
        var cacheWrite1hTokens: Int

        static let zero = ModelTokenBreakdown(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, cacheWrite1hTokens: 0)
        var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens + cacheWrite1hTokens }
    }

    struct ParsedFile: Equatable {
        let days: [String: Int]
        /// day → model → tokens separados por tipo de input.
        let modelDays: [String: [String: ModelTokenBreakdown]]
    }

    struct FileDigest: Codable, Equatable {
        static let currentFormatVersion = 3

        /// Versão sem default propositalmente: caches do formato anterior falham o decode
        /// e são reconstruídos uma única vez com o breakdown por modelo.
        let formatVersion: Int
        let mtime: Double
        let size: Int64
        let days: [String: Int]
        let modelDays: [String: [String: ModelTokenBreakdown]]
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
    /// o diretório não existe (Claude Code não instalado). Nunca lança. O breakdown por
    /// modelo cobre os últimos 30 dias porque é a janela usada para equivalência de custo.
    func analytics(windowDays: Int = 365, now: Date = Date()) -> TokenAnalytics? {
        guard FileManager.default.fileExists(atPath: projectsDir) else { return nil }
        loadCacheIfNeeded()

        let files = jsonlFiles()
        guard !files.isEmpty else { return nil }

        var mergedDays: [String: Int] = [:]
        var mergedModelDays: [String: [String: ModelTokenBreakdown]] = [:]
        var newCache: [String: FileDigest] = [:]
        var cacheChanged = false

        struct FileAttributesSnapshot {
            let path: String
            let mtime: Double
            let size: Int64
        }

        var snapshots: [FileAttributesSnapshot] = []
        snapshots.reserveCapacity(files.count)
        for file in files {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file),
                  let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate,
                  let size = (attributes[.size] as? NSNumber)?.int64Value
            else { continue }
            snapshots.append(FileAttributesSnapshot(path: file, mtime: mtime, size: size))
        }

        // Parse é a parte cara e os arquivos são independentes. O scanner antigo lia os
        // 6GB do corpus serialmente; aqui até oito workers bastam para saturar SSD/CPU sem
        // mapear dezenas de transcripts gigantes ao mesmo tempo. Resultados entram no
        // array por índice, então não há estado compartilhado mutável.
        var digests = [FileDigest?](repeating: nil, count: snapshots.count)
        var parseJobs: [(index: Int, snapshot: FileAttributesSnapshot)] = []
        for (index, snapshot) in snapshots.enumerated() {
            if let cached = cache[snapshot.path], cached.formatVersion == FileDigest.currentFormatVersion,
               cached.mtime == snapshot.mtime, cached.size == snapshot.size {
                digests[index] = cached
            } else {
                parseJobs.append((index, snapshot))
            }
        }

        if !parseJobs.isEmpty {
            let parallelism = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount))
            let slots = DispatchSemaphore(value: parallelism)
            let digestLock = NSLock()
            DispatchQueue.concurrentPerform(iterations: parseJobs.count) { jobIndex in
                slots.wait()
                let job = parseJobs[jobIndex]
                let parsed = Self.parseFileDetailed(atPath: job.snapshot.path)
                let digest = FileDigest(
                    formatVersion: FileDigest.currentFormatVersion,
                    mtime: job.snapshot.mtime,
                    size: job.snapshot.size,
                    days: parsed.days,
                    modelDays: parsed.modelDays
                )
                digestLock.lock()
                digests[job.index] = digest
                digestLock.unlock()
                slots.signal()
            }
            cacheChanged = true
        }


        for (index, snapshot) in snapshots.enumerated() {
            guard let digest = digests[index] else { continue }
            newCache[snapshot.path] = digest
            for (day, tokens) in digest.days {
                mergedDays[day, default: 0] += tokens
            }
            for (day, byModel) in digest.modelDays {
                var mergedModels = mergedModelDays[day] ?? [:]
                for (model, tokens) in byModel {
                    var existing = mergedModels[model] ?? .zero
                    existing.inputTokens += tokens.inputTokens
                    existing.outputTokens += tokens.outputTokens
                    existing.cacheReadTokens += tokens.cacheReadTokens
                    existing.cacheWriteTokens += tokens.cacheWriteTokens
                    existing.cacheWrite1hTokens += tokens.cacheWrite1hTokens
                    mergedModels[model] = existing
                }
                mergedModelDays[day] = mergedModels
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

        let costCutoff = TokenAnalytics.dayKey(now.addingTimeInterval(-30 * 24 * 3600))
        var totalsByModel: [String: ModelTokenBreakdown] = [:]
        for (day, byModel) in mergedModelDays where day >= costCutoff {
            for (model, tokens) in byModel {
                var existing = totalsByModel[model] ?? .zero
                existing.inputTokens += tokens.inputTokens
                existing.outputTokens += tokens.outputTokens
                existing.cacheReadTokens += tokens.cacheReadTokens
                existing.cacheWriteTokens += tokens.cacheWriteTokens
                existing.cacheWrite1hTokens += tokens.cacheWrite1hTokens
                totalsByModel[model] = existing
            }
        }
        let details = totalsByModel
            .filter { $0.value.totalTokens > 0 }
            .map {
                UsageDetail(
                    modelId: $0.key,
                    promptTokens: $0.value.inputTokens,
                    completionTokens: $0.value.outputTokens,
                    cacheReadTokens: $0.value.cacheReadTokens,
                    cacheWriteTokens: $0.value.cacheWriteTokens,
                    cacheWrite1hTokens: $0.value.cacheWrite1hTokens
                )
            }
            .sorted { $0.modelId < $1.modelId }

        return TokenAnalytics(usageDetails: details.isEmpty ? nil : details, dailyBuckets: buckets)
    }

    // MARK: - Parsing de um arquivo

    /// Totais por dia de um único .jsonl. Mantido para testes e para chamadas antigas;
    /// `parseFileDetailed` é a fonte completa.
    static func parseFile(atPath path: String) -> [String: Int] {
        parseFileDetailed(atPath: path).days
    }

    /// Totais por dia e por modelo de um único .jsonl. Estático e puro (fora o I/O) para
    /// ser testável.
    static func parseFileDetailed(atPath path: String) -> ParsedFile {
        // `.mappedIfSafe` + busca binária evitam a dupla cópia que tornava o cold scan
        // inviável em corpora grandes: antes cada transcript inteiro virava `String` e
        // `split` retia o buffer completo, mesmo quando 99% das linhas não tinham usage.
        // Aqui só as linhas candidatas são materializadas para o parser JSON.
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return ParsedFile(days: [:], modelDays: [:])
        }

        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let usageNeedle = Data("\"usage\"".utf8)
        let assistantNeedle = Data("\"assistant\"".utf8)

        var days: [String: Int] = [:]
        var modelDays: [String: [String: ModelTokenBreakdown]] = [:]
        var seen = Set<String>()
        var preParsedSeen = Set<String>()

        var lineStart = data.startIndex
        while lineStart < data.endIndex {
            let lineEnd = data[lineStart...].firstIndex(of: 0x0a) ?? data.endIndex
            let line = data[lineStart..<lineEnd]
            lineStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex

            // Filtro barato antes do JSON: só linhas de assistant com usage interessam.
            guard line.range(of: usageNeedle) != nil, line.range(of: assistantNeedle) != nil else { continue }

            // Streaming repete a mesma mensagem dezenas de vezes com o mesmo usage. As
            // chaves estruturais podem ser extraídas por bytes com segurança porque aspas
            // dentro do conteúdo textual chegam escapadas (\\"), nunca como a sequência
            // crua \"requestId\":\". Pular essas repetições evita parsear centenas de MB
            // de JSON que seriam descartados pelo `seen` logo depois.
            let preMessageId = stringValue(in: line, key: "id", prefix: "msg_")
            let preRequestId = stringValue(in: line, key: "requestId")
            if !(preMessageId ?? "").isEmpty || !(preRequestId ?? "").isEmpty {
                guard preParsedSeen.insert((preMessageId ?? "") + "#" + (preRequestId ?? "")).inserted else { continue }
            }

            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestampRaw = object["timestamp"] as? String,
                  let timestamp = isoWithFraction.date(from: timestampRaw) ?? iso.date(from: timestampRaw)
            else { continue }

            // Streaming grava a mesma mensagem em várias linhas conforme os blocos
            // chegam. O usage observado se repete nessas linhas, então cada combinação
            // id+requestId pode contar uma única vez.
            let messageId = message["id"] as? String ?? ""
            let requestId = object["requestId"] as? String ?? ""
            if !messageId.isEmpty || !requestId.isEmpty {
                guard seen.insert("\(messageId)#\(requestId)").inserted else { continue }
            }

            // `cache_creation_input_tokens` é o total; o objeto `cache_creation` separa
            // TTL de 5min e 1h. Quando ele falta em versões antigas, tratamos tudo como
            // 5min — fallback conservador, porque é o preço menor e não inventa TTL longo.
            let cacheCreation = usage["cache_creation"] as? [String: Any]
            let totalCacheWrite = intValue(usage["cache_creation_input_tokens"])
            var cacheWrite5m = intValue(cacheCreation?["ephemeral_5m_input_tokens"])
            var cacheWrite1h = intValue(cacheCreation?["ephemeral_1h_input_tokens"])
            if cacheWrite5m + cacheWrite1h == 0 {
                cacheWrite5m = totalCacheWrite
                cacheWrite1h = 0
            }
            let breakdown = ModelTokenBreakdown(
                inputTokens: intValue(usage["input_tokens"]),
                outputTokens: intValue(usage["output_tokens"]),
                cacheReadTokens: intValue(usage["cache_read_input_tokens"]),
                cacheWriteTokens: cacheWrite5m,
                cacheWrite1hTokens: cacheWrite1h
            )
            guard breakdown.totalTokens > 0 else { continue }

            let day = TokenAnalytics.dayKey(timestamp)
            days[day, default: 0] += breakdown.totalTokens

            let model = message["model"] as? String ?? "unknown"
            var byModel = modelDays[day] ?? [:]
            var existing = byModel[model] ?? .zero
            existing.inputTokens += breakdown.inputTokens
            existing.outputTokens += breakdown.outputTokens
            existing.cacheReadTokens += breakdown.cacheReadTokens
            existing.cacheWriteTokens += breakdown.cacheWriteTokens
            existing.cacheWrite1hTokens += breakdown.cacheWrite1hTokens
            byModel[model] = existing
            modelDays[day] = byModel
        }
        return ParsedFile(days: days, modelDays: modelDays)
    }

    /// Extrai um valor string simples de uma linha JSON sem materializar o objeto
    /// inteiro. Usado apenas para deduplicação barata; os números de uso continuam sendo
    /// lidos pelo parser JSON real, então um formato inesperado degrada para o caminho
    /// completo em vez de virar token inventado.
    private static func stringValue(in data: Data, key: String, prefix: String? = nil) -> String? {
        let needle = Data(("\"" + key + "\":\"").utf8)
        guard let range = data.range(of: needle) else { return nil }
        var end = range.upperBound
        var escaped = false
        while end < data.endIndex {
            let byte = data[end]
            if byte == 0x22 && !escaped { break } // "
            if byte == 0x5c { // \
                escaped.toggle()
            } else {
                escaped = false
            }
            end = data.index(after: end)
        }
        guard end < data.endIndex else { return nil }
        guard let value = String(data: data[range.upperBound..<end], encoding: .utf8) else { return nil }
        if let prefix, !value.hasPrefix(prefix) { return nil }
        return value
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
