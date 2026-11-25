import Foundation

/// Extração tolerante de JSON para contratos internos de IDEs/CLIs que mudam sem aviso.
/// O princípio é o oposto de um `Codable` rígido: aceita número como número ou string,
/// procura campos em formatos camelCase/snake_case e ignora tudo o que o app não consome.
enum TolerantJSON {
    static func object(data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [[String: Any]]? {
        value as? [[String: Any]]
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Float: return Double(value)
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String where !value.isEmpty: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String:
            let normalized = value.lowercased()
            if ["true", "1", "yes"].contains(normalized) { return true }
            if ["false", "0", "no"].contains(normalized) { return false }
            return nil
        default: return nil
        }
    }

    /// Busca direta aceitando variações do mesmo nome (`totalSpend`/`total_spend`).
    static func value(in object: [String: Any], camel: String) -> Any? {
        if let value = object[camel] { return value }
        let snake = camel.reduce(into: "") { result, character in
            if character.isUppercase {
                result += "_" + character.lowercased()
            } else {
                result.append(character)
            }
        }
        return object[snake]
    }

    static func number(in object: [String: Any], camel: String) -> Double? {
        number(value(in: object, camel: camel))
    }

    static func string(in object: [String: Any], camel: String) -> String? {
        string(value(in: object, camel: camel))
    }

    /// Procura uma chave em qualquer profundidade. Serve só como compatibilidade com
    /// envelopes (`response`, `result`) e campos que os serviços movem de nível — nunca
    /// para inferir cotas de texto livre.
    static func deepValue(for key: String, in value: Any?) -> Any? {
        if let object = object(value) {
            if let direct = object[key] { return direct }
            for nested in object.values {
                if let found = deepValue(for: key, in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = deepValue(for: key, in: nested) { return found }
            }
        }
        return nil
    }

    static func isoDate(_ value: Any?) -> Date? {
        guard let string = string(value) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    static func unixDate(_ value: Any?) -> Date? {
        guard let seconds = number(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
