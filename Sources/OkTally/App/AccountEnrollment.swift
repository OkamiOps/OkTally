// Sources/OkTally/App/AccountEnrollment.swift
import Foundation

/// Adicionar uma conta extra: um RASCUNHO recebe um id (`AccountID.nextId`), o login grava
/// a credencial sob esse id, e só então `finish` descobre quem é a conta e decide.
///
/// A conta só entra na lista depois do login — nunca existe uma conta "meio adicionada"
/// polindo o scheduler com erro de "não configurado". E a mesma identidade no mesmo tipo
/// é recusada: acompanhar a mesma conta duas vezes só dobraria as chamadas (e os 429 do
/// Claude) sem mostrar nada novo.
@MainActor
final class AccountEnrollment {
    enum Result: Equatable {
        case committed
        /// Já existe uma conta com a mesma identidade; a credencial do rascunho foi apagada.
        case duplicate(email: String?)
        /// O rascunho deixou de ser o ativo (cancelado ou trocado) antes de terminar; nada
        /// foi adicionado e a credencial dele foi apagada.
        case cancelled
        case failed
    }

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Id do rascunho. Reaproveita o id legado quando ele está livre.
    func beginDraft(kind: AccountKind) -> String {
        let id = AccountID.nextId(kind: kind, existing: model.accounts.map(\.id))
        model.activeDraftId = id
        return id
    }

    /// Pode gravar credencial sob `id`? Só para conta existente ou o rascunho ativo. É o
    /// que impede o auto-save de um painel que está sumindo (conta recém-removida) de
    /// regravar a chave morta no Keychain.
    func acceptsCredential(for id: String) -> Bool {
        model.accounts.contains { $0.id == id } || model.activeDraftId == id
    }

    /// Chamado depois que o login gravou a credencial sob `draftId`.
    func finish(draftId: String, kind: AccountKind) async -> Result {
        guard !model.accounts.contains(where: { $0.id == draftId }) else { return .failed }
        var account = AccountInstance(id: draftId, kind: kind)
        guard model.activeDraftId == draftId else {
            try? model.credentialEraser?(account)
            return .cancelled
        }
        let identity = await model.identityResolver?(account) ?? AccountIdentity()
        // A descoberta da identidade é assíncrona: o dono pode ter cancelado (ou começado
        // outro rascunho) enquanto isso. `abandon` já apagou o token, mas um commit aqui
        // criaria uma conta zumbi sem credencial.
        guard model.activeDraftId == draftId else {
            try? model.credentialEraser?(account)
            return .cancelled
        }
        if AccountDedup.isDuplicate(identityKey: identity.identityKey, kind: kind,
                                    among: model.accounts, excluding: draftId) {
            // A credencial gravada sob o rascunho é de uma conta que já acompanhamos:
            // apagá-la evita um token órfão no Keychain.
            try? model.credentialEraser?(account)
            return .duplicate(email: identity.email)
        }
        account.email = identity.email
        account.identityKey = identity.identityKey
        account.autoLabel = identity.autoLabel
        model.commitAccount(account)
        if model.activeDraftId == draftId { model.activeDraftId = nil }
        return .committed
    }

    /// O dono desistiu do rascunho: apaga o que o login possa ter gravado. Nunca toca
    /// numa conta já adicionada (o id do rascunho só coincide com uma se algo deu errado).
    func abandon(draftId: String, kind: AccountKind) {
        if model.activeDraftId == draftId { model.activeDraftId = nil }
        guard !model.accounts.contains(where: { $0.id == draftId }) else { return }
        try? model.credentialEraser?(AccountInstance(id: draftId, kind: kind))
    }
}
