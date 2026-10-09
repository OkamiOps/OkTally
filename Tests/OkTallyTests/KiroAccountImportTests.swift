import XCTest
@testable import OkTally

final class KiroAccountImportTests: XCTestCase {
    private func token(profile: String? = "profile/work", email: String = "me@example.test") -> OAuthToken {
        var extra = ["email": email]
        extra["profileArn"] = profile
        return OAuthToken(accessToken: "example", refreshToken: nil, expiresAt: nil, extra: extra)
    }

    func test_reimportPreservesAccountIdentity() throws {
        let existing = AccountInstance(id: "kiro", kind: .kiro, identityKey: "profile/work")
        XCTAssertNoThrow(try KiroAccountImport.validate(token(), replacing: existing))
        XCTAssertThrowsError(try KiroAccountImport.validate(token(profile: "profile/personal"), replacing: existing)) {
            XCTAssertTrue($0 is KiroAccountImportError)
        }
        XCTAssertNoThrow(try KiroAccountImport.validate(token(profile: "profile/personal"), replacing: nil))
    }

    func test_unidentifiedSessionCannotBeImported() {
        XCTAssertThrowsError(try KiroAccountImport.validate(token(profile: nil, email: "   "), replacing: nil))
    }
}
