// Tests/OkTallyTests/ClaudeLocalUsageScannerTests.swift
import XCTest
@testable import OkTally

final class ClaudeLocalUsageScannerTests: XCTestCase {
    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: dir + "/projeto-a", withIntermediateDirectories: true)
        return dir
    }

    private func usageLine(day: String, msgId: String, reqId: String, input: Int, output: Int, cacheCreate: Int = 0, cacheRead: Int = 0) -> String {
        """
        {"type":"assistant","timestamp":"\(day)T15:00:00.000Z","requestId":"\(reqId)","message":{"id":"\(msgId)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cacheCreate),"cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    func test_parseFile_sumsTokensPerDay_includingCache() throws {
        let dir = try makeTempDir()
        let path = dir + "/projeto-a/s1.jsonl"
        let content = [
            usageLine(day: "2026-08-10", msgId: "m1", reqId: "r1", input: 10, output: 20, cacheCreate: 100, cacheRead: 200),
            #"{"type":"user","timestamp":"2026-08-10T15:01:00.000Z","message":{"role":"user"}}"#,
            usageLine(day: "2026-08-11", msgId: "m2", reqId: "r2", input: 1, output: 2),
        ].joined(separator: "\n")
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        let days = ClaudeLocalUsageScanner.parseFile(atPath: path)

        XCTAssertEqual(days["2026-08-10"], 330)
        XCTAssertEqual(days["2026-08-11"], 3)
    }

    func test_parseFile_deduplicatesByMessageAndRequestId() throws {
        let dir = try makeTempDir()
        let path = dir + "/projeto-a/s1.jsonl"
        // Streaming grava a mesma mensagem duas vezes com usage cumulativo — só a
        // primeira ocorrência conta.
        let content = [
            usageLine(day: "2026-08-10", msgId: "m1", reqId: "r1", input: 10, output: 5),
            usageLine(day: "2026-08-10", msgId: "m1", reqId: "r1", input: 10, output: 50),
            usageLine(day: "2026-08-10", msgId: "m3", reqId: "r3", input: 1, output: 1),
        ].joined(separator: "\n")
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        let days = ClaudeLocalUsageScanner.parseFile(atPath: path)

        XCTAssertEqual(days["2026-08-10"], 15 + 2)
    }

    func test_analytics_mergesFilesAndUsesCacheAcrossCalls() throws {
        let dir = try makeTempDir()
        try FileManager.default.createDirectory(atPath: dir + "/projeto-b", withIntermediateDirectories: true)
        try usageLine(day: "2026-08-10", msgId: "a", reqId: "ra", input: 100, output: 0)
            .write(toFile: dir + "/projeto-a/s1.jsonl", atomically: true, encoding: .utf8)
        try usageLine(day: "2026-08-10", msgId: "b", reqId: "rb", input: 50, output: 0)
            .write(toFile: dir + "/projeto-b/s2.jsonl", atomically: true, encoding: .utf8)
        let cachePath = dir + "/cache.json"

        let scanner = ClaudeLocalUsageScanner(projectsDir: dir, cachePath: cachePath)
        let now = TokenAnalytics.date(fromDay: "2026-08-12")!
        let analytics = try XCTUnwrap(scanner.analytics(now: now))

        XCTAssertEqual(analytics.tokens(onDay: "2026-08-10"), 150)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath), "cache deve ser persistido")

        // Segunda instância lê do cache persistido e chega ao mesmo resultado.
        let scanner2 = ClaudeLocalUsageScanner(projectsDir: dir, cachePath: cachePath)
        let analytics2 = try XCTUnwrap(scanner2.analytics(now: now))
        XCTAssertEqual(analytics2.tokens(onDay: "2026-08-10"), 150)
    }

    func test_analytics_missingDirectory_returnsNil() {
        let scanner = ClaudeLocalUsageScanner(projectsDir: "/nonexistent/claude/projects", cachePath: nil)
        XCTAssertNil(scanner.analytics())
    }
    func test_parseFileDetailed_preservesModelAndCacheBreakdown() throws {
        let dir = try makeTempDir()
        let path = dir + "/projeto-a/s1.jsonl"
        let line = """
        {"type":"assistant","timestamp":"2026-08-10T15:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":100,"cache_read_input_tokens":200}}}
        """
        try line.write(toFile: path, atomically: true, encoding: .utf8)

        let parsed = ClaudeLocalUsageScanner.parseFileDetailed(atPath: path)

        let breakdown = try XCTUnwrap(parsed.modelDays["2026-08-10"]?["claude-opus-5"])
        XCTAssertEqual(breakdown.inputTokens, 10)
        XCTAssertEqual(breakdown.outputTokens, 20)
        XCTAssertEqual(breakdown.cacheWriteTokens, 100)
        XCTAssertEqual(breakdown.cacheReadTokens, 200)
    }

    func test_analytics_exposesLast30DayUsageDetailsForPricing() throws {
        let dir = try makeTempDir()
        let line = """
        {"type":"assistant","timestamp":"2026-08-10T15:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":100,"cache_read_input_tokens":200}}}
        """
        try line.write(toFile: dir + "/projeto-a/s1.jsonl", atomically: true, encoding: .utf8)
        let now = TokenAnalytics.date(fromDay: "2026-08-12")!

        let analytics = try XCTUnwrap(ClaudeLocalUsageScanner(projectsDir: dir, cachePath: nil).analytics(now: now))
        let detail = try XCTUnwrap(analytics.usageDetails?.first)

        XCTAssertEqual(detail.modelId, "claude-opus-5")
        XCTAssertEqual(detail.promptTokens, 10)
        XCTAssertEqual(detail.completionTokens, 20)
        XCTAssertEqual(detail.cacheWriteTokens, 100)
        XCTAssertEqual(detail.cacheReadTokens, 200)
    }

    func test_parseFileDetailed_splitsCacheWriteByTTL() throws {
        let dir = try makeTempDir()
        let path = dir + "/projeto-a/s1.jsonl"
        let line = """
        {"type":"assistant","timestamp":"2026-08-10T15:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":100,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":25,"ephemeral_1h_input_tokens":75}}}}
        """
        try line.write(toFile: path, atomically: true, encoding: .utf8)

        let parsed = ClaudeLocalUsageScanner.parseFileDetailed(atPath: path)
        let breakdown = try XCTUnwrap(parsed.modelDays["2026-08-10"]?["claude-opus-5"])

        XCTAssertEqual(breakdown.cacheWriteTokens, 25)
        XCTAssertEqual(breakdown.cacheWrite1hTokens, 75)
        XCTAssertEqual(parsed.days["2026-08-10"], 100)
    }

}
