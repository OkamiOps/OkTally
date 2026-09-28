// Sources/OkTally/Plugins/MiMo/MiMoConsoleHost.swift
import Foundation

/// Onde a web view está parada dentro da cadeia do SSO.
enum MiMoConsoleLocation: Equatable {
    /// `platform.xiaomimimo.com`: dá para falar com a API.
    case console
    /// `account.xiaomi.com`: o SSO está no meio do caminho (ou pedindo login de verdade).
    case login
    /// `about:blank`, erro de rede, qualquer outro domínio.
    case unknown
}

/// Endereços fixos do console do MiMo.
///
/// O fetch antigo era relativo (`fetch('/api/v1/tokenPlan/usage')`), resolvido contra a
/// página *carregada naquele instante*. No meio da cadeia (console → `account.xiaomi.com/pass/serviceLogin`
/// → `/sts` → volta) isso virava `https://account.xiaomi.com/api/v1/tokenPlan/usage`: um 404
/// em HTML que nunca foi o uso do plano. URL absoluta + conferência de host resolvem os dois
/// lados do problema — o request vai para o lugar certo, e sabemos quando nem vale pedir.
enum MiMoConsoleHost {
    static let consoleDomain = "xiaomimimo.com"
    static let loginDomain = "account.xiaomi.com"

    static let planManageURL = URL(string: "https://platform.xiaomimimo.com/#/console/plan-manage")!
    static let usageURL = URL(string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage")!

    static func location(of url: URL?) -> MiMoConsoleLocation {
        guard let host = url?.host?.lowercased() else { return .unknown }
        if host == consoleDomain || host.hasSuffix("." + consoleDomain) { return .console }
        if host == loginDomain || host.hasSuffix("." + loginDomain) { return .login }
        return .unknown
    }
}
