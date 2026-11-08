import XCTest
import ReviewCore
@testable import EvidenceWorkbench

final class AppCredentialsTests: XCTestCase {
    private func keyFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".env")
        try Data(contents.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testConfiguredKeyFileTakesPrecedenceOverKeychain() throws {
        let file = try keyFile("OPENAI_API_KEY=file-synthetic-value\n")
        XCTAssertEqual(try AppCredentials.resolve(fileURL: file, keychain: { "keychain-synthetic-value" }), "file-synthetic-value")
    }
    func testKeyFileWithoutTheVariableFallsBackToKeychain() throws {
        let file = try keyFile("OTHER=1\n")
        XCTAssertEqual(try AppCredentials.resolve(fileURL: file, keychain: { "keychain-synthetic-value" }), "keychain-synthetic-value")
    }
    func testUnreadableKeyFileIsReportedInsteadOfSilentlyUsingKeychain() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".env")
        XCTAssertThrowsError(try AppCredentials.resolve(fileURL: missing, keychain: { "keychain-synthetic-value" }), "A deleted or moved key file must not switch billing to the Keychain key.")
        let target = try keyFile("OPENAI_API_KEY=file-synthetic-value\n")
        let link = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".env")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        addTeardownBlock { try? FileManager.default.removeItem(at: link) }
        XCTAssertThrowsError(try AppCredentials.resolve(fileURL: link, keychain: { "keychain-synthetic-value" })) { error in
            XCTAssertTrue(error.localizedDescription.contains("symbolic link"), "The symlink refusal must reach the user, got: \(error.localizedDescription)")
        }
    }
    func testKeyFileWithoutVariableAndEmptyKeychainReportsMissingKey() throws {
        let file = try keyFile("OTHER=1\n")
        XCTAssertThrowsError(try AppCredentials.resolve(fileURL: file, keychain: { "" })) { error in
            guard case WorkbenchError.missingKey = error else { return XCTFail("Expected missingKey, got \(error)") }
        }
    }
    func testMissingEverywhereReportsMissingKey() {
        XCTAssertThrowsError(try AppCredentials.resolve(fileURL: nil, keychain: { "" })) { error in
            guard case WorkbenchError.missingKey = error else { return XCTFail("Expected missingKey, got \(error)") }
        }
    }
}
