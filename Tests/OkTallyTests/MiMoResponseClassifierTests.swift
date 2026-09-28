import XCTest
@testable import OkTally

final class MiMoResponseClassifierTests: XCTestCase {
    private func classify(_ body: String) -> MiMoResponseKind {
        MiMoResponseClassifier.classify(Data(body.utf8))
    }

    func test_usageJSON_isUsable() {
        XCTAssertEqual(classify(#"{"code":0,"data":{"usage":{"percent":0.5}}}"#), .usable)
    }

    func test_jsonWithoutCode_isUsable() {
        // Nem toda resposta do console traz `code`; sem prova de 401 o corpo segue para o
        // decoder, que sabe reclamar melhor do que um palpite nosso.
        XCTAssertEqual(classify(#"{"data":{"usage":{"percent":0.5}}}"#), .usable)
    }

    func test_401_isUnauthorized_regardlessOfSpacingOrOrder() {
        // O match antigo era a string literal `"code":401`: qualquer espaço do servidor
        // (ou `code` depois de outro campo) passava batido e virava erro de decode.
        XCTAssertEqual(classify(#"{"code":401,"msg":"unauthorized"}"#), .unauthorized)
        XCTAssertEqual(classify(#"{ "code" : 401 , "msg" : "x" }"#), .unauthorized)
        XCTAssertEqual(classify(#"{"msg":"unauthorized","code":401}"#), .unauthorized)
        XCTAssertEqual(classify("{\n  \"code\": 401\n}"), .unauthorized)
    }

    func test_401AsString_isUnauthorized() {
        XCTAssertEqual(classify(#"{"code":"401","msg":"unauthorized"}"#), .unauthorized)
    }

    func test_xiaomiLoginPageHTML_isUnauthorized() {
        // Quando o STS morre, o fetch é redirecionado e volta o HTML do SSO em vez do JSON.
        let html = "<!DOCTYPE html><html><head><title>小米账号</title></head>" +
            "<body><form action=\"https://account.xiaomi.com/pass/serviceLogin\"></form></body></html>"
        XCTAssertEqual(classify(html), .unauthorized)
    }

    func test_unrelatedHTMLOrEmptyBody_isUnusable() {
        // Um gateway 502 ou a SPA ainda bootando não é prova de logout — é um tick perdido.
        XCTAssertEqual(classify("<html><body>502 Bad Gateway</body></html>"), .unusable)
        XCTAssertEqual(classify(""), .unusable)
        XCTAssertEqual(classify("   \n "), .unusable)
        XCTAssertEqual(classify("null"), .unusable)
    }
}

final class MiMoConsoleLocationTests: XCTestCase {
    func test_consoleHost_isConsole() {
        XCTAssertEqual(MiMoConsoleHost.location(of: URL(string: "https://platform.xiaomimimo.com/#/console/plan-manage")), .console)
        XCTAssertEqual(MiMoConsoleHost.location(of: URL(string: "https://PLATFORM.XiaomiMiMo.com/api/v1/tokenPlan/usage")), .console)
    }

    func test_xiaomiSSOHost_isLogin() {
        XCTAssertEqual(MiMoConsoleHost.location(of: URL(string: "https://account.xiaomi.com/pass/serviceLogin?sid=api-platform")), .login)
        XCTAssertEqual(MiMoConsoleHost.location(of: URL(string: "https://account.xiaomi.com/sts?ticket=x")), .login)
    }

    func test_nilOrForeignHost_isUnknown() {
        XCTAssertEqual(MiMoConsoleHost.location(of: nil), .unknown)
        XCTAssertEqual(MiMoConsoleHost.location(of: URL(string: "about:blank")), .unknown)
        XCTAssertEqual(MiMoConsoleHost.location(of: URL(string: "https://example.com/")), .unknown)
    }

    func test_usageURL_isAbsolute_onTheConsoleHost() {
        // O fetch relativo (`/api/v1/tokenPlan/usage`) resolvia contra a página carregada:
        // no meio da cadeia do SSO isso batia em account.xiaomi.com e nunca em MiMo.
        XCTAssertEqual(MiMoConsoleHost.usageURL.absoluteString, "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage")
        XCTAssertEqual(MiMoConsoleHost.location(of: MiMoConsoleHost.usageURL), .console)
    }
}
