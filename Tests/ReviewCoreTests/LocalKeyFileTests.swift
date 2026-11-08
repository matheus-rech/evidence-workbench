import XCTest
@testable import ReviewCore

final class LocalKeyFileTests: XCTestCase {
    func testReadsOnlyExpectedVariableWithoutExecutingContent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("OTHER=ignored\nOPENAI_API_KEY=\"synthetic-test-value\"\n$(never-execute)\n".utf8).write(to: url)
        XCTAssertEqual(try LocalKeyFile.read(url), "synthetic-test-value")
    }
    func testSymlinkRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("actual"); try Data("OPENAI_API_KEY=synthetic".utf8).write(to: file)
        let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try LocalKeyFile.read(link))
    }
}
