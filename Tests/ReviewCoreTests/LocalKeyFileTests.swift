import XCTest
@testable import ReviewCore

final class LocalKeyFileTests: XCTestCase {
    func testReadsOnlyExpectedVariableWithoutExecutingContent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("OTHER=ignored\nOPENAI_API_KEY=\"synthetic-test-value\"\n$(never-execute)\n".utf8).write(to: url)
        XCTAssertEqual(try LocalKeyFile.read(url), "synthetic-test-value")
    }
    func testPresentButMalformedKeyIsNotReportedAsAbsent() throws {
        // `missingKey` means "this file has no OPENAI_API_KEY line" and is the only error that lets the app fall back to
        // the Keychain. A line that is present but empty or broken must be reported as its own error.
        for line in ["OPENAI_API_KEY=", "OPENAI_API_KEY=   ", "OPENAI_API_KEY=\"\"", "OPENAI_API_KEY=bad token", "OPENAI_API_KEY=''"] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            try Data((line + "\n").utf8).write(to: url)
            XCTAssertThrowsError(try LocalKeyFile.read(url), line) { error in
                if case WorkbenchError.missingKey = error { XCTFail("\(line) was reported as an absent variable") }
                XCTAssertTrue(error.localizedDescription.contains("OPENAI_API_KEY"), "The error must name the variable: \(error.localizedDescription)")
                XCTAssertFalse(error.localizedDescription.contains("bad token"), "The error must not echo the file's value")
            }
        }
    }
    func testFileWithoutTheVariableIsReportedAsAbsent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("OTHER=1\n# OPENAI_API_KEY is set elsewhere\n".utf8).write(to: url)
        XCTAssertThrowsError(try LocalKeyFile.read(url)) { error in
            guard case WorkbenchError.missingKey = error else { return XCTFail("Expected missingKey, got \(error)") }
        }
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
