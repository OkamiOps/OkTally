import XCTest
@testable import OkTally

final class FakeCredentialStoreReading: CredentialStoreReading {
    var dataToReturn: Data?
    func readClaudeCredentialsJSON() -> Data? { dataToReturn }
}

final class ClaudeCredentialProviderTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    func test_keychainHit_decodesWrappedShape() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = """
        {"claudeAiOauth":{"accessToken":"abc123","refreshToken":"r1","expiresAt":1700000000000}}
        """.data(using: .utf8)
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        let credentials = try provider.loadCredentials()

        XCTAssertEqual(credentials.accessToken, "abc123")
    }

    func test_keychainMiss_fallsBackToFile() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = nil
        let fileURL = tempFileURL()
        try """
        {"claudeAiOauth":{"accessToken":"fromfile","refreshToken":null,"expiresAt":null}}
        """.data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: fileURL)

        let credentials = try provider.loadCredentials()

        XCTAssertEqual(credentials.accessToken, "fromfile")
    }

    func test_keychainMissAndNoFile_throwsNotFound() {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = nil
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        XCTAssertThrowsError(try provider.loadCredentials()) { error in
            XCTAssertEqual(error as? ClaudeCredentialError, .notFound)
        }
    }

    func test_malformedJSON_throwsMalformed() {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = "not json".data(using: .utf8)
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        XCTAssertThrowsError(try provider.loadCredentials()) { error in
            XCTAssertEqual(error as? ClaudeCredentialError, .malformed)
        }
    }

    func test_flatShape_alsoDecodes() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = """
        {"accessToken":"flat123","refreshToken":null,"expiresAt":null}
        """.data(using: .utf8)
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        let credentials = try provider.loadCredentials()

        XCTAssertEqual(credentials.accessToken, "flat123")
    }
}
