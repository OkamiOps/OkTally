// Sources/OkTally/Plugins/OpenCode/OpenCodeRateLimitParser.swift
import Foundation

/// Parses OpenCode's HTTP 429 rate-limit error bodies (`FreeUsageLimitError` /
/// `GoUsageLimitError`), the one place OpenCode's inference API leaks any usage state —
/// confirmed by reading `packages/opencode/src/session/retry.ts` in `sst/opencode`.
/// These errors follow the same effect-ts tagged-error shape seen elsewhere in the
/// codebase (e.g. the live-probed `DeviceTokenError`/`Unauthorized` bodies from the OAuth
/// device-code flow): a `_tag` discriminator plus a `metadata` payload. When such an error
/// is observed it is the authoritative "you are at the limit" signal and should override
/// the local estimate for the matching window until `resetAt`.
enum OpenCodeRateLimitParser {
    private struct ErrorBody: Decodable {
        struct Metadata: Decodable {
            let limitName: String?
        }
        let _tag: String?
        let metadata: Metadata?
    }

    /// Returns the exceeded window's `limitName` and, when `retry-after` is present and
    /// parseable, the estimated reset time. Returns `nil` for any non-429 response, any
    /// body that isn't a recognized OpenCode usage-limit error, or a body missing
    /// `metadata.limitName`.
    static func parse(statusCode: Int, body: Data, retryAfterHeader: String?) -> (limitName: String, resetAt: Date?)? {
        guard statusCode == 429 else { return nil }
        guard let decoded = try? JSONDecoder().decode(ErrorBody.self, from: body) else { return nil }
        guard let tag = decoded._tag, tag == "GoUsageLimitError" || tag == "FreeUsageLimitError" else { return nil }
        guard let limitName = decoded.metadata?.limitName else { return nil }

        var resetAt: Date?
        if let retryAfterHeader, let seconds = Double(retryAfterHeader) {
            resetAt = Date().addingTimeInterval(seconds)
        }
        return (limitName, resetAt)
    }
}
