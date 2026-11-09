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
    func testSavingLegacyReviewUsesVersionTwoWithoutChangingItsIdentity() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let repo=ProjectRepository(root:root);var old=ReviewProject();old.schemaVersion=1
        let folder=root.appendingPathComponent(old.id.uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONEncoder().encode(old).write(to:folder.appendingPathComponent("project.json"))
        let before = try await repo.list(); let legacy=try XCTUnwrap(before.projects.first)
        XCTAssertEqual(legacy.schemaVersion,1)
        let saved=try await repo.save(legacy);XCTAssertEqual(saved.schemaVersion,2);XCTAssertEqual(saved.id,old.id)
        let listing=try await repo.list();XCTAssertEqual(listing.projects.first?.schemaVersion,2)
    }

}
