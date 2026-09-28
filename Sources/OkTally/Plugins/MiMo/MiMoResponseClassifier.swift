// Sources/OkTally/Plugins/MiMo/MiMoResponseClassifier.swift
import Foundation

/// O que o corpo devolvido pelo console do MiMo nos autoriza a concluir.
enum MiMoResponseKind: Equatable {
    /// Parece o JSON de uso: entrega ao decoder.
    case usable
    /// Prova de sessão morta *neste momento*: `code` 401 ou o HTML do SSO da Xiaomi.
    /// Recuperável por reload — não é veredito de logout definitivo.
    case unauthorized
    /// Nem JSON do console nem login: SPA ainda bootando, gateway mudo, corpo vazio.
    /// Um tick perdido, e nada além disso.
    case unusable
}

/// Lê o corpo do `tokenPlan/usage` sem confiar em formatação.
///
/// O teste antigo era `text.contains("\"code\":401")`: um único espaço do servidor
/// (`"code" : 401`) ou o campo vindo depois de outro já escapava, e a resposta seguia para
/// o `JSONDecoder`, que estourava com um erro de decode — classificado como falha genérica
/// em vez de sessão expirada. Aqui o JSON é parseado de verdade, e um corpo que não é JSON
/// é julgado pelo que ele é (página de login × ruído transitório) em vez de virar 401.
enum MiMoResponseClassifier {
    static func classify(_ data: Data) -> MiMoResponseKind {
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .unusable }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // `code` chega como número na API e como string em alguns gateways do SSO.
            return code(in: object) == 401 ? .unauthorized : .usable
        }
        // Não é um objeto JSON: só pode ser página, e aí o host dentro dela é o que importa.
        return looksLikeXiaomiLogin(text) ? .unauthorized : .unusable
    }

    private static func code(in object: [String: Any]) -> Int? {
        switch object["code"] {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    /// A marca do SSO: o redirect de `sid=api-platform` sempre aterrissa em um documento que
    /// cita `account.xiaomi.com` (form action, canonical ou script de redirecionamento).
    private static func looksLikeXiaomiLogin(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("account.xiaomi.com")
            || lowered.contains("servicelogin")
            || lowered.contains("passtoken")
    }
}
