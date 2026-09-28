// Sources/OkTally/Plugins/MiMo/MiMoSessionRecovery.swift
import Foundation

/// The STS cookie behind the MiMo console expires long before the Xiaomi SSO session
/// does. A 401 therefore usually means "stale STS", not "logged out" — reloading the
/// console page re-runs the SSO redirect chain and mints a fresh STS. Only a 401 that
/// survives that reload means the SSO itself is dead and the user must log in again.
///
/// Os cookies de sessão do console são *session-only*: eles morrem quando o app fecha, e
/// só o `passToken` da Xiaomi sobrevive em disco. Ou seja, TODO lançamento começa com um
/// 401 e depende desta recuperação para funcionar — ela é o caminho normal, não a exceção.
/// É `final class` (não `struct`) porque precisa lembrar qual foi a última falha entre as
/// duas tentativas para distinguir "sessão morta" de "tick perdido".
final class MiMoSessionRecovery {
    private let fetch: () async throws -> Data
    private let reload: () async throws -> Void
    private var lastFailure: MiMoConsoleError?

    init(fetch: @escaping () async throws -> Data, reload: @escaping () async throws -> Void) {
        self.fetch = fetch
        self.reload = reload
    }

    func fetchWithRecovery() async throws -> Data {
        if let data = try await usableBody() { return data }
        MiMoLog.session.notice("recovery: primeiro fetch inutilizável (\(self.failureLabel, privacy: .public)) — recarregando console")
        try await reload()
        if let data = try await usableBody() {
            MiMoLog.session.notice("recovery: reload recuperou a sessão")
            return data
        }
        let failure = lastFailure ?? .notLoggedIn
        MiMoLog.session.error("recovery: 2ª tentativa também falhou (\(self.failureLabel, privacy: .public))")
        throw failure
    }

    /// Devolve o corpo quando ele serve, ou `nil` anotando em `lastFailure` o motivo. Erros
    /// que não são do console (rede, `-999`) sobem intactos: reload não é remédio para eles.
    private func usableBody() async throws -> Data? {
        let data: Data
        do {
            data = try await fetch()
        } catch let error as MiMoConsoleError {
            // A web view podia estar parada no SSO quando o tick começou — isso o reload cura.
            lastFailure = error
            return nil
        }
        switch MiMoResponseClassifier.classify(data) {
        case .usable:
            return data
        case .unauthorized:
            lastFailure = .notLoggedIn
            return nil
        case .unusable:
            lastFailure = .noData
            return nil
        }
    }

    private var failureLabel: String {
        switch lastFailure {
        case .notLoggedIn: return "401/login"
        case .noData: return "corpo inutilizável"
        case .sessionRecovering: return "em recuperação"
        case nil: return "desconhecido"
        }
    }
}
