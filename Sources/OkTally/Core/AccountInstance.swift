// Sources/OkTally/Core/AccountInstance.swift
import Foundation
import CryptoKit

/// Uma conta que o dono acompanha. `id` é a chave em todo o app (ver `AccountID`);
/// `kind` diz que provedor ela é. Nada aqui é segredo: e-mail e apelido moram nas
/// preferências, as credenciais continuam no Keychain sob o próprio `id`.
struct AccountInstance: Codable, Equatable, Identifiable {
    let id: String
    let kind: AccountKind
    /// Apelido escolhido pelo dono ("Trabalho"). `nil` = nunca deu nome.
    var nickname: String?
    /// E-mail descoberto depois do login — rótulo automático, não identidade.
    var email: String?
    /// Chave de dedup (e-mail normalizado, ou impressão digital da chave de API).
    var identityKey: String?
    /// Rótulo automático quando não há e-mail — hoje, o `label` que o OpenRouter devolve
    /// para a chave (o nome dela, ou a chave mascarada `sk-or-v1-0e6...1c96`).
    var autoLabel: String?

    init(id: String, kind: AccountKind, nickname: String? = nil, email: String? = nil,
         identityKey: String? = nil, autoLabel: String? = nil) {
        self.id = id
        self.kind = kind
        self.nickname = nickname
        self.email = email
        self.identityKey = identityKey
        self.autoLabel = autoLabel
    }
}

/// O que se descobre sobre uma conta depois do login (ou da chave salva).
struct AccountIdentity: Equatable {
    var email: String?
    var identityKey: String?
    var autoLabel: String?

    init(email: String? = nil, identityKey: String? = nil, autoLabel: String? = nil) {
        self.email = email
        self.identityKey = identityKey
        self.autoLabel = autoLabel
    }

    var isEmpty: Bool { email == nil && identityKey == nil && autoLabel == nil }
}

enum AccountsCatalog {
    /// Uma conta legada por tipo, na MESMA ordem em que o app registrava os provedores
    /// antes das contas múltiplas. Sem GrokBot: ele nasce do Cursor (ver `ProviderFactory`).
    static let defaultAccounts: [AccountInstance] = [
        .claude, .codex, .openrouter, .minimax, .cursor, .copilot,
        .antigravity, .opencode, .mimo, .supergrok
    ].map { AccountInstance(id: $0.rawValue, kind: $0) }
}

enum AccountLabel {
    /// Nome exibido de uma conta. Quem tem uma conta só de um tipo e nunca deu apelido
    /// vê exatamente o nome de sempre; o sufixo só aparece quando ajuda a distinguir.
    static func display(for account: AccountInstance, baseName: String, siblings: [AccountInstance]) -> String {
        if let nickname = account.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            return "\(baseName) · \(nickname)"
        }
        let sameKind = siblings.filter { $0.kind == account.kind }
        guard sameKind.count > 1 else { return baseName }
        if let email = account.email, !email.isEmpty {
            return "\(baseName) · \(email)"
        }
        if let autoLabel = account.autoLabel, !autoLabel.isEmpty {
            return "\(baseName) · \(autoLabel)"
        }
        let position = (sameKind.firstIndex { $0.id == account.id } ?? sameKind.count) + 1
        return "\(baseName) · \(position)"
    }
}

enum AccountDedup {
    /// A mesma identidade no mesmo tipo é a mesma conta — acompanhá-la duas vezes só
    /// duplicaria chamadas (e os 429 do Claude). Identidade desconhecida nunca bloqueia.
    static func isDuplicate(identityKey: String?, kind: AccountKind, among accounts: [AccountInstance], excluding id: String) -> Bool {
        guard let key = identityKey?.lowercased(), !key.isEmpty else { return false }
        return accounts.contains { $0.kind == kind && $0.id != id && $0.identityKey?.lowercased() == key }
    }

    /// Identidade de uma conta de chave de API: `key:` + 16 hex do SHA-256 da chave.
    /// Só serve para comparar — não dá para voltar à chave, e ela nunca é gravada.
    static func fingerprint(apiKey: String) -> String {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return "key:" + digest.map { String(format: "%02x", $0) }.joined().prefix(16)
    }
}

/// Consulta rápida sobre as contas, para quem desenha: o glifo com ordinal ("C2") que
/// separa contas irmãs na barra de menu e o rótulo curto do notch.
struct AccountDirectory {
    let accounts: [AccountInstance]

    static let empty = AccountDirectory(accounts: [])

    /// A conta dona de um provedor (o GrokBot pertence à conta do Cursor dele).
    func account(forProviderId id: String) -> AccountInstance? {
        let accountId = AccountID.kind(of: id) == .grokbot ? AccountID.cursorId(forGrokBot: id) : id
        return accounts.first { $0.id == accountId }
    }

    /// Posição (1…) da conta entre as do mesmo tipo, na ordem da lista.
    func ordinal(of id: String) -> Int? {
        guard let account = account(forProviderId: id) else { return nil }
        let siblings = accounts.filter { $0.kind == account.kind }
        return siblings.firstIndex { $0.id == account.id }.map { $0 + 1 }
    }

    /// Glifo do tipo, com o ordinal a partir da SEGUNDA conta. Quem tem uma conta só de
    /// cada tipo vê exatamente os glifos de sempre.
    func glyph(for id: String) -> String {
        let base = ProviderPalette.baseGlyph(forId: id)
        guard let ordinal = ordinal(of: id), ordinal > 1 else { return base }
        return "\(base)\(ordinal)"
    }

    /// Rótulo curto para onde a largura é pouca (notch): o apelido, ou o começo do
    /// e-mail, ou o rótulo automático — só quando há irmãs do mesmo tipo para distinguir.
    func shortLabel(for id: String) -> String? {
        guard let account = account(forProviderId: id) else { return nil }
        if let nickname = account.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            return nickname
        }
        guard accounts.filter({ $0.kind == account.kind }).count > 1 else { return nil }
        if let email = account.email, let local = email.split(separator: "@").first, !local.isEmpty {
            return String(local)
        }
        if let autoLabel = account.autoLabel, !autoLabel.isEmpty { return autoLabel }
        return ordinal(of: id).map { "#\($0)" }
    }
}

/// O diretório vigente, para código estático que não recebe o modelo (a paleta é
/// chamada de dentro do `ImageRenderer` da barra de menu). Mesmo padrão do
/// `UsageColorScaleHolder`: só o `AppModel` escreve aqui.
enum AccountDirectoryHolder {
    static var current: AccountDirectory = .empty
}
