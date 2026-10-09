import XCTest
@testable import OkTally

final class KiroAccountImportTests: XCTestCase {
    private func token(profile: String? = "profile/work", userId: String? = "user-one", email: String = "me@example.test") -> OAuthToken {
        var extra = ["email": email]
        extra["profileArn"] = profile
        extra["userId"] = userId
        return OAuthToken(accessToken: "example", refreshToken: nil, expiresAt: nil, extra: extra)
    }

    func test_reimportPreservesAccountIdentity() throws {
        let existing = AccountInstance(id: "kiro", kind: .kiro, identityKey: "profile/work|user:user-one")
        XCTAssertNoThrow(try KiroAccountImport.validate(token(), replacing: existing))
        XCTAssertThrowsError(try KiroAccountImport.validate(token(userId: "user-two"), replacing: existing))
        XCTAssertThrowsError(try KiroAccountImport.validate(token(profile: "profile/personal"), replacing: existing))
        XCTAssertNoThrow(try KiroAccountImport.validate(token(profile: "profile/personal"), replacing: nil))
    }

    func test_twoUsersSharingOrganizationProfileRemainSeparateAccounts() {
        let first = KiroAccountImport.identity(from: token())
        let second = KiroAccountImport.identity(from: token(userId: "user-two", email: "other@example.test"))
        let existing = AccountInstance(id: "kiro", kind: .kiro, identityKey: first.identityKey)
        XCTAssertNotEqual(first.identityKey, second.identityKey)
        XCTAssertFalse(AccountDedup.isDuplicate(identityKey: second.identityKey, kind: .kiro, among: [existing], excluding: "kiro#other"))
    }

    func test_profileAloneIsNotAnAccountIdentity() {
        XCTAssertThrowsError(try KiroAccountImport.validate(token(userId: nil, email: "   "), replacing: nil))
        XCTAssertThrowsError(try KiroAccountImport.validate(token(profile: nil, userId: nil, email: "   "), replacing: nil))
    }

    func test_emailFallbackIsScopedToOrganizationAndNormalized() {
        let identity = KiroAccountImport.identity(from: token(userId: nil, email: " Me@Example.test "))
        XCTAssertEqual(identity.identityKey, "profile/work|email:me@example.test")
    }
}
