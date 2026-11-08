import XCTest
@testable import ReviewCore
final class IntegrityTests: XCTestCase {
    func testLoaderRejectsDuplicateObservationIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let repo = ProjectRepository(root: root); var p = ReviewProject()
        let d = SourceDocument(filename: "x.txt", relativePath: "documents/x.txt", sha256: "x", pages: [.init(number: 1, text: "x")]);p.documents = [d]
        let row = Observation(documentID: d.id, variableID: "title", value: "x");p.observations = [row,row]
        let folder = root.appendingPathComponent(p.id.uuidString);try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true);try JSONEncoder().encode(p).write(to: folder.appendingPathComponent("project.json"))
        let list = try await repo.list(); XCTAssertTrue(list.projects.isEmpty);XCTAssertEqual(list.failures.count,1)
    }
    func testLegacyVerifiedWithoutEvidenceIsQuarantinedWithoutDeletingValue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let repo = ProjectRepository(root: root);var p = ReviewProject();let d = SourceDocument(filename: "x.txt", relativePath: "documents/x.txt", sha256: "x", pages: [.init(number: 1, text: "x")]);p.documents = [d]
        p.observations = [.init(documentID: d.id, variableID: "title", value: "legacy", status: .verified, reviewer: "Old reviewer")]
        _ = try await repo.save(p);let loaded = try await repo.list().projects.first
        XCTAssertEqual(loaded?.observations.first?.value,"legacy");XCTAssertEqual(loaded?.observations.first?.status,.edited)
        XCTAssertTrue(loaded?.audit.contains { $0.action == "Verification quarantined" } == true)
    }
}
