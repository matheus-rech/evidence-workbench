import XCTest
@testable import ReviewCore

final class RegionEvidenceTests: XCTestCase {
    func testVisualEvidenceNeedsExplicitCheckingAndRetainsDifferentProvenance() throws {
        let document = SourceDocument(filename: "scan.pdf", relativePath: "scan.pdf", sha256: "fixture", pages: [.init(number: 1, text: "")])
        let variable = VariableDefinition(id: "value", label: "Value", definition: "Reported cell", type: .number)
        var row = Observation(documentID: document.id, variableID: variable.id, value: "42", citations: [.init(page: 1, quote: "42", region: .init(x: 0.2, y: 0.3, width: 0.1, height: 0.05))])
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: variable, reviewer: "QA", document: document))
        row.citations[0].visuallyVerified = true
        let checked = try ReviewEngine.verify(row, variable: variable, reviewer: "QA", document: document)
        XCTAssertEqual(checked.status, .verified)
        XCTAssertFalse(checked.citations[0].exactMatch)
        XCTAssertNil(checked.citations[0].startUTF16)
        XCTAssertEqual(checked.citations[0].region, row.citations[0].region)
        let suggestion = try ReviewEngine.validated(checked, variable: variable, document: document)
        XCTAssertNil(suggestion.citations[0].visuallyVerified)
        XCTAssertEqual(suggestion.status, .suggested)
        let edited = ReviewEngine.edited(checked, value: "43", missingness: .reported, context: checked.context, note: "Corrected")
        XCTAssertTrue(edited.citations.isEmpty)
    }
    func testInvalidAndNonfiniteRegionsCannotBeVerified() throws {
        let document = SourceDocument(filename: "scan.pdf", relativePath: "scan.pdf", sha256: "fixture", pages: [.init(number: 1, text: "42")])
        let variable = VariableDefinition(id: "value", label: "Value", definition: "Reported cell", type: .number)
        for region in [EvidenceRegion(x: -0.1, y: 0, width: 0.2, height: 0.2), .init(x: 0.9, y: 0, width: 0.2, height: 0.2), .init(x: 0, y: 0, width: 0, height: 0.2), .init(x: .nan, y: 0, width: 0.2, height: 0.2)] {
            let row = Observation(documentID: document.id, variableID: variable.id, value: "42", citations: [.init(page: 1, quote: "42", region: region, visuallyVerified: true)])
            XCTAssertThrowsError(try ReviewEngine.verify(row, variable: variable, reviewer: "QA", document: document))
        }
    }
    func testOlderCitationDecodesWithoutRegionAndRegionRoundTrips() throws {
        let old = try JSONDecoder().decode(EvidenceCitation.self, from: Data("{\"page\":1,\"quote\":\"42\",\"exactMatch\":true}".utf8))
        XCTAssertNil(old.region); XCTAssertNil(old.visuallyVerified)
        let citation = EvidenceCitation(page: 3, quote: "42", region: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.4), visuallyVerified: true)
        XCTAssertEqual(try JSONDecoder().decode(EvidenceCitation.self, from: JSONEncoder().encode(citation)), citation)
    }
    func testCSVPreservesVisualRegionAndDoesNotCallItATextMatch() throws {
        var project = ReviewProject(title: "Visual evidence export")
        let source = SourceDocument(filename: "scan.pdf", relativePath: "scan.pdf", sha256: "fixture", pages: [.init(number: 1, text: "")])
        project.documents = [source]
        project.observations = [.init(documentID: source.id, variableID: "age_mean", value: "42", citations: [.init(page: 1, quote: "42", region: .init(x: 0.2, y: 0.3, width: 0.1, height: 0.05), visuallyVerified: true)], status: .verified)]
        project.observations[0] = try ReviewEngine.verify(project.observations[0], variable: project.plan.variables.first { $0.id == "age_mean" }!, reviewer: "QA", document: source)
        let csv = DatasetExporter.longCSV(project, verifiedOnly: true)
        XCTAssertTrue(csv.contains("source_regions_normalized")); XCTAssertTrue(csv.contains("visual_source_checked"))
        XCTAssertTrue(csv.contains("x=0.2;y=0.3;width=0.1;height=0.05"))
        XCTAssertTrue(csv.contains("\"true\",\"false\""))
    }
}
