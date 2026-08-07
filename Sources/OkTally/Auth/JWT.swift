// Sources/OkTally/Auth/JWT.swift
import Foundation

/// Minimal, unsigned JWT payload reader.
///
/// This is intentionally NOT a verifier: it does not check the signature, issuer, or
/// expiry. It exists only to opportunistically read auxiliary claims (e.g. an account id)
/// off an `id_token` we already received directly from a provider's token endpoint over
/// TLS during an authorization-code exchange. We never use the decoded claims to
/// authenticate anything — the access token remains the sole credential presented to
/// resource servers. If decoding fails for any reason (malformed token, unexpected shape),
/// callers should treat that as "no extra claims available" and continue without error.
enum JWT {
    /// Decodes the middle (payload) segment of a compact JWT (`header.payload.signature`)
    /// into a loosely-typed JSON object. Returns `nil` if the token isn't a 3-segment JWT
    /// or the payload segment isn't valid base64url-encoded JSON.
    static func decodePayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }
        guard let data = base64urlDecode(String(segments[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func base64urlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        return Data(base64Encoded: base64)
    }
}
