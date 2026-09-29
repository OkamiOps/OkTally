import XCTest
@testable import OkTally

final class MiMoNavigationErrorTests: XCTestCase {
    func test_nsURLErrorCancelled_isSupersededNavigation() {
        let error = NSError(domain: "NSURLErrorDomain", code: -999)
        XCTAssertTrue(MiMoNavigationError.isSupersededNavigation(error))
    }

    func test_webKitFrameLoadInterrupted_isSupersededNavigation() {
        let error = NSError(domain: "WebKitErrorDomain", code: 102)
        XCTAssertTrue(MiMoNavigationError.isSupersededNavigation(error))
    }

    func test_otherNSURLErrorCodes_areNotSuperseded() {
        // -1009 (offline), -1001 (timed out) etc. são falhas de verdade: quem espera
        // `ensureConsoleLoaded` precisa saber disso, não engolir como "aguarde mais".
        let offline = NSError(domain: "NSURLErrorDomain", code: -1009)
        let timedOut = NSError(domain: "NSURLErrorDomain", code: -1001)
        XCTAssertFalse(MiMoNavigationError.isSupersededNavigation(offline))
        XCTAssertFalse(MiMoNavigationError.isSupersededNavigation(timedOut))
    }

    func test_sameCodeInAnotherDomain_isNotSuperseded() {
        // O código -999 só significa "navegação superada" no domínio da própria URL loading.
        let error = NSError(domain: "com.example.other", code: -999)
        XCTAssertFalse(MiMoNavigationError.isSupersededNavigation(error))
    }

    func test_arbitraryError_isNotSuperseded() {
        struct Boom: Error {}
        XCTAssertFalse(MiMoNavigationError.isSupersededNavigation(Boom()))
    }
}
