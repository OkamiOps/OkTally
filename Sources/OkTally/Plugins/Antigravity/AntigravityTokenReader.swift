// Sources/OkTally/Plugins/Antigravity/AntigravityTokenReader.swift
import Foundation
import GRDB

struct AntigravityTokens: Equatable {
    let accessToken: String
    let refreshToken: String
}

protocol AntigravityTokenReading {
    func readTokens() -> AntigravityTokens?
}

/// Lê o login do IDE Antigravity no `state.vscdb` dele (mesma exceção sancionada do
/// Cursor: sem o IDE logado não há uso para medir; qualquer problema degrada para nil).
///
/// O valor da chave `antigravityUnifiedStateSync.oauthToken` é base64 de um protobuf com
/// entradas repetidas `field 1 { field 1: sentinel, field 2 { field 1: payload } }`; a
/// entrada com sentinel `oauthTokenInfoSentinelKey` carrega OUTRO base64 de protobuf:
/// `field 1: access_token, field 2: "Bearer", field 3: refresh_token, field 4: expiry`.
/// Formato confirmado ao vivo em 2026-08-12 decodificando o banco real (estrutura
/// idêntica à que o Quotio manipula no formato "novo", >= 1.16.5).
final class AntigravityTokenReader: AntigravityTokenReading {
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/Library/Application Support/Antigravity/User/globalStorage/state.vscdb") {
        self.dbPath = dbPath
    }

    func readTokens() -> AntigravityTokens? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var config = Configuration()
        config.readonly = true
        guard let dbQueue = try? DatabaseQueue(path: dbPath, configuration: config) else { return nil }

        let blob: String? = try? dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken'"
            ) else { return nil }
            if let string: String = row["value"] { return string }
            if let data: Data = row["value"] { return String(data: data, encoding: .utf8) }
            return nil
        }
        guard let blob else { return nil }
        return Self.decodeTokens(fromBase64: blob)
    }

    // MARK: - Protobuf decode (mínimo necessário, sem dependência)

    static func decodeTokens(fromBase64 blob: String) -> AntigravityTokens? {
        guard let outer = decodeBase64(blob) else { return nil }
        for (field, value) in (try? parseFields(outer)) ?? [] {
            guard field == 1, case .bytes(let entry) = value,
                  let entryFields = try? parseFields(entry),
                  case .bytes(let sentinel)? = entryFields.first(where: { $0.0 == 1 })?.1,
                  String(data: sentinel, encoding: .utf8) == "oauthTokenInfoSentinelKey",
                  case .bytes(let wrap)? = entryFields.first(where: { $0.0 == 2 })?.1,
                  case .bytes(let innerB64)? = (try? parseFields(wrap))?.first(where: { $0.0 == 1 })?.1,
                  let innerString = String(data: innerB64, encoding: .utf8),
                  let oauth = decodeBase64(innerString),
                  let oauthFields = try? parseFields(oauth),
                  case .bytes(let access)? = oauthFields.first(where: { $0.0 == 1 })?.1,
                  case .bytes(let refresh)? = oauthFields.first(where: { $0.0 == 3 })?.1,
                  let accessToken = String(data: access, encoding: .utf8),
                  let refreshToken = String(data: refresh, encoding: .utf8),
                  !accessToken.isEmpty, !refreshToken.isEmpty
            else { continue }
            return AntigravityTokens(accessToken: accessToken, refreshToken: refreshToken)
        }
        return nil
    }

    enum ProtoValue: Equatable {
        case varint(UInt64)
        case bytes(Data)
    }

    private struct ProtoError: Error {}

    /// Parser de wire format: só varint (0) e length-delimited (2) — o suficiente para
    /// este payload; qualquer outro wire type aborta com erro (→ nil no chamador).
    static func parseFields(_ data: Data) throws -> [(UInt32, ProtoValue)] {
        var result: [(UInt32, ProtoValue)] = []
        var index = data.startIndex
        while index < data.endIndex {
            let (tag, afterTag) = try readVarint(data, from: index)
            let field = UInt32(tag >> 3)
            let wireType = tag & 0x7
            switch wireType {
            case 0:
                let (value, next) = try readVarint(data, from: afterTag)
                result.append((field, .varint(value)))
                index = next
            case 2:
                let (length, payloadStart) = try readVarint(data, from: afterTag)
                guard let end = data.index(payloadStart, offsetBy: Int(length), limitedBy: data.endIndex) else {
                    throw ProtoError()
                }
                result.append((field, .bytes(Data(data[payloadStart..<end]))))
                index = end
            default:
                throw ProtoError()
            }
        }
        return result
    }

    private static func readVarint(_ data: Data, from start: Data.Index) throws -> (UInt64, Data.Index) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < data.endIndex {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, index) }
            shift += 7
            if shift > 63 { throw ProtoError() }
        }
        throw ProtoError()
    }

    /// Base64 tolerante a padding ausente (o blob do IDE vem sem `=`).
    private static func decodeBase64(_ string: String) -> Data? {
        var padded = string
        let remainder = padded.count % 4
        if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: padded)
    }

    // MARK: - Suporte a teste

    /// Constrói um blob no mesmo formato do IDE — usado só nos testes para exercitar o
    /// decoder com um payload sintético.
    static func encodeTestBlob(accessToken: String, refreshToken: String) -> String {
        func varint(_ value: UInt64) -> Data {
            var v = value
            var out = Data()
            repeat {
                var byte = UInt8(v & 0x7F)
                v >>= 7
                if v > 0 { byte |= 0x80 }
                out.append(byte)
            } while v > 0
            return out
        }
        func lenField(_ field: UInt32, _ payload: Data) -> Data {
            var out = Data()
            out.append(varint(UInt64(field << 3 | 2)))
            out.append(varint(UInt64(payload.count)))
            out.append(payload)
            return out
        }
        var oauth = Data()
        oauth.append(lenField(1, Data(accessToken.utf8)))
        oauth.append(lenField(2, Data("Bearer".utf8)))
        oauth.append(lenField(3, Data(refreshToken.utf8)))
        let innerB64 = oauth.base64EncodedString()
        let wrap = lenField(1, Data(innerB64.utf8))
        var entry = Data()
        entry.append(lenField(1, Data("oauthTokenInfoSentinelKey".utf8)))
        entry.append(lenField(2, wrap))
        let outer = lenField(1, entry)
        return outer.base64EncodedString()
    }
}
