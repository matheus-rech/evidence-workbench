import XCTest
@testable import ReviewCore

final class SourceAssetTests: XCTestCase {
    func testAssetRejectsWrongHashAndMismatchedTableProvenance() throws {
        let document = SourceDocument(filename: "trial.pdf", relativePath: "trial.pdf", sha256: "source", pages: [.init(number: 7, text: "Table 1")])
        var asset = SourceAsset(documentID: document.id, sourceSHA256: "source", page: 7, kind: .table, label: "Table 1", title: "Population")
        XCTAssertNoThrow(try asset.validate(document: document))
        asset.table = EditableTable(title: "Population", columns: ["Group", "N"], rows: [["Control", "235"]], sourceFilename: "trial.pdf", sourceSHA256: "wrong", page: 7, region: asset.region)
        XCTAssertThrowsError(try asset.validate(document: document))
        asset.table = nil; asset.sourceSHA256 = "wrong"
        XCTAssertThrowsError(try asset.validate(document: document))
    }
    func testRerunPreservesReviewedAssetsAndRoundTripPersists() throws {
        var saved = SourceAsset(documentID: UUID(), sourceSHA256: "source", page: 7, kind: .table, label: "Table 1", title: "Checked")
        saved.reviewedAt = Date(); saved.reviewedBy = "QA"
        var incoming = saved; incoming.id = UUID(); incoming.title = "New AI draft"; incoming.reviewedAt = nil
        XCTAssertEqual(SourceAsset.merge(existing: [saved], incoming: [incoming]), [saved])
        var project = ReviewProject(); project.assets = [saved]
        XCTAssertEqual(try JSONDecoder().decode(ReviewProject.self, from: JSONEncoder().encode(project)).assets, [saved])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any]); json.removeValue(forKey: "assets")
        XCTAssertNil(try JSONDecoder().decode(ReviewProject.self, from: JSONSerialization.data(withJSONObject: json)).assets)
    }
}
