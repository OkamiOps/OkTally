import XCTest
import CryptoKit
@testable import OkTally

final class PKCETests: XCTestCase {
    func test_makeVerifier_lengthInRange_urlSafe() {
        let v = PKCE.makeVerifier()
        XCTAssertTrue((43...128).contains(v.count))
        XCTAssertNil(v.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~").inverted))
    }

    func test_challenge_matchesManualSha256Base64url() {
        let verifier = "test-verifier-string-1234567890abcdef"
        let expected = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(PKCE.challenge(for: verifier), expected)
    }

    func test_parseCode_extractsCodeWhenStateMatches() {
        let path = "/callback?code=abc123&state=xyz"
        XCTAssertEqual(PKCE.parseCode(fromCallbackPath: path, expectedState: "xyz"), "abc123")
    }

    func test_parseCode_nilWhenStateMismatch() {
        let path = "/callback?code=abc123&state=wrong"
        XCTAssertNil(PKCE.parseCode(fromCallbackPath: path, expectedState: "xyz"))
    }

    func test_parseCode_nilWhenNoCode() {
        XCTAssertNil(PKCE.parseCode(fromCallbackPath: "/callback?state=xyz", expectedState: "xyz"))
    }

    func test_challenge_matchesRFC7636AppendixBVector() {
        // https://datatracker.ietf.org/doc/html/rfc7636#appendix-B
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(PKCE.challenge(for: verifier), expected)
    }
}
