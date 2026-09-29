// Sources/OkTally/Plugins/MiMo/MiMoNavigationError.swift
import Foundation

/// Distingue uma navegação que falhou de verdade de uma que só foi atropelada por outra.
///
/// A cadeia do SSO da Xiaomi (console → `account.xiaomi.com/pass/serviceLogin` → `/sts` →
/// volta para o console) é uma sequência de redirects em JS. Quando um load supera o
/// anterior — ou o próprio SSO troca de página no meio do caminho — o WebKit reporta a
/// navegação SUPERADA como erro: `NSURLErrorDomain -999` (`NSURLErrorCancelled`) ou
/// `WebKitErrorDomain 102` ("Frame load interrupted"). Isso não é uma falha: um `didFinish`
/// de verdade ainda está a caminho. Resolver os waiters de `ensureConsoleLoaded` com esse
/// erro bruto era exatamente o que vazava "NSURLErrorDomain error -999" para o popover.
enum MiMoNavigationError {
    private static let nsURLErrorDomain = "NSURLErrorDomain"
    private static let nsURLErrorCancelled = -999
    private static let webKitErrorDomain = "WebKitErrorDomain"
    private static let webKitFrameLoadInterrupted = 102

    static func isSupersededNavigation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == nsURLErrorDomain, ns.code == nsURLErrorCancelled { return true }
        if ns.domain == webKitErrorDomain, ns.code == webKitFrameLoadInterrupted { return true }
        return false
    }
}
