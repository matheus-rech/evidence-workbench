import XCTest
@testable import ReviewCore

final class ReviewEngineTests: XCTestCase {
    func source() -> SourceDocument { .init(filename: "article.pdf", relativePath: "documents/example.pdf", sha256: "test", pages: [.init(number: 1, text: "Mean age was 68.5 years.\nThere were 0 events among 50 participants.")]) }
    func field(_ id: String = "age_mean", type: FieldType = .number) -> VariableDefinition { .init(id: id, label: "Age", definition: "Arithmetic mean age", type: type) }
    func observation() -> Observation { .init(documentID: sourceID, variableID: "age_mean", value: "68.5", citations: [.init(page: 1, quote: "Mean age was 68.5 years.")], confidence: 1) }
    private let sourceID = UUID()
    func paired() -> (SourceDocument, Observation) {
        var doc = source(); doc.id = sourceID
        return (doc, observation())
    }
    func testPlanRequiresPICOTTReviewerAndApproval() {
        var plan = ReviewPlan()
        XCTAssertFalse(plan.readyForArticles)
        plan.researchQuestion = "Does treatment improve survival?"
        plan.picott.population = "Adults"; plan.picott.intervention = "Treatment"; plan.picott.comparator = "Usual care"
        plan.picott.outcomes = "Survival"; plan.picott.timing = "12 months"; plan.picott.studyTypes = "Randomized trials"
        plan.reviewer = "Reviewer A"
        plan.extractionProcess = "Two independent reviewers with adjudication"
        plan.riskOfBiasTool = "RoB 2"
        plan.synthesisPlan = "Risk ratios at 12 months; separately report cluster trials."
        XCTAssertTrue(plan.validationMessages.isEmpty)
        XCTAssertFalse(plan.readyForArticles)
        plan.approvedAt = Date(); XCTAssertTrue(plan.readyForArticles)
        plan.picott.timing = "  "; XCTAssertFalse(plan.readyForArticles)
    }
    func testRemovingCoreFieldBlocksApproval() {
        var plan = ReviewPlan(); plan.variables.removeFirst()
        XCTAssertTrue(plan.validationMessages.contains { $0.contains("core") })
    }
    func testConfidenceOneStaysOne() throws {
        let (doc, row) = paired()
        XCTAssertEqual(try ReviewEngine.validated(row, variable: field(), document: doc).confidence, 1)
    }
    func testConfidenceOutsideRangeRejected() {
        var (doc, row) = paired(); row.confidence = 101
        XCTAssertThrowsError(try ReviewEngine.validated(row, variable: field(), document: doc))
        doc.id = UUID(); XCTAssertThrowsError(try ReviewEngine.validated(row, variable: field(), document: doc))
    }
    func testQuoteCheckedAgainstNamedPage() throws {
        let (doc, row) = paired()
        XCTAssertTrue(try ReviewEngine.validated(row, variable: field(), document: doc).citations[0].exactMatch)
        var invalid = row; invalid.citations[0].quote = "Mean age was 99 years."
        XCTAssertFalse(try ReviewEngine.validated(invalid, variable: field(), document: doc).citations[0].exactMatch)
        invalid.citations[0].page = 99
        XCTAssertThrowsError(try ReviewEngine.validated(invalid, variable: field(), document: doc))
    }
    func testQuoteWhitespaceNormalizationWithoutPunctuationErasure() {
        XCTAssertEqual(ReviewEngine.normalizeQuote("Mean\n age   68.5"), "Mean age 68.5")
        XCTAssertNotEqual(ReviewEngine.normalizeQuote("6.85"), ReviewEngine.normalizeQuote("68.5"))
    }
    func testEditInvalidatesSourceConfidenceAndVerification() {
        var (_, row) = paired(); row.status = .verified; row.reviewer = "A"
        let edited = ReviewEngine.edited(row, value: "99", missingness: .reported, context: row.context, note: "Corrected")
        XCTAssertEqual(edited.status, .edited); XCTAssertTrue(edited.citations.isEmpty); XCTAssertNil(edited.confidence); XCTAssertTrue(edited.reviewer.isEmpty)
    }
    func testVerificationRequiresReviewerAndSource() throws {
        let (doc, row) = paired()
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field(), reviewer: "", document: doc))
        var unsourced = row; unsourced.citations = []
        XCTAssertThrowsError(try ReviewEngine.verify(unsourced, variable: field(), reviewer: "A", document: doc))
        let verified = try ReviewEngine.verify(row, variable: field(), reviewer: "A", document: doc)
        XCTAssertEqual(verified.status, .verified); XCTAssertEqual(verified.reviewer, "A")
    }
    func testMissingnessRequiresReasonAndDoesNotBecomeZero() throws {
        let (doc, original) = paired(); var row = original; row.value = ""; row.missingness = .notReported; row.citations = []
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field(), reviewer: "A", document: doc))
        row.note = "Checked full report and supplement; not stated."
        XCTAssertEqual(try ReviewEngine.verify(row, variable: field(), reviewer: "A", document: doc).value, "")
        XCTAssertNoThrow(try ReviewEngine.validateValue("0", missingness: .reported, type: .integer))
        XCTAssertThrowsError(try ReviewEngine.validateValue("0", missingness: .notReported, type: .integer))
    }
    func testTypedValuesRejectUnitsNaNAndInvalidDates() {
        XCTAssertThrowsError(try ReviewEngine.validateValue("68.5 years", missingness: .reported, type: .number))
        XCTAssertThrowsError(try ReviewEngine.validateValue("nan", missingness: .reported, type: .number))
        XCTAssertThrowsError(try ReviewEngine.validateValue("2.5", missingness: .reported, type: .integer))
        XCTAssertThrowsError(try ReviewEngine.validateValue("2026-02-30", missingness: .reported, type: .date))
        XCTAssertNoThrow(try ReviewEngine.validateValue("2024-02-29", missingness: .reported, type: .date))
    }
    func testChunkingPreservesAllTextAndPageNumbers() {
        let pages = [DocumentPage(number: 1, text: "abcdefghijk"), DocumentPage(number: 2, text: "😀😀two"), DocumentPage(number: 3, text: "")]
        let chunks = ReviewEngine.extractionChunks(pages, limit: 4)
        XCTAssertTrue(chunks.allSatisfy { $0.map(\.text).joined().count <= 4 })
        XCTAssertEqual(chunks.flatMap { $0 }.map(\.text).joined(), pages.map(\.text).joined())
        XCTAssertTrue(chunks.flatMap { $0 }.contains { $0.number == 3 })
    }
    func testConsolidationDoesNotCollapseArmsOrTimepoints() {
        let docID = UUID()
        let a = Observation(documentID: docID, variableID: "events", value: "2", context: .init(arm: "A", outcome: "Death", timepoint: "6 months"))
        var b = a; b.id = UUID(); b.context.arm = "B"
        var c = a; c.id = UUID(); c.context.timepoint = "12 months"
        XCTAssertEqual(ReviewEngine.consolidate([a, a, b, c]).count, 3)
    }
    func testCSVIncludesProvenanceAndPreventsFormulaInjection() {
        var project = ReviewProject(); let doc = source(); project.documents = [doc]
        project.observations = [.init(documentID: doc.id, variableID: "title", value: "=HYPERLINK(\"https://example.org\",\"x\")", citations: [.init(page: 1, quote: "Quoted, with \"punctuation\"\nand a line break", exactMatch: true)])]
        let csv = DatasetExporter.longCSV(project, verifiedOnly: false)
        XCTAssertTrue(csv.contains("source_quotes")); XCTAssertTrue(csv.contains("'=HYPERLINK")); XCTAssertTrue(csv.contains("\"\"punctuation\"\""))
        XCTAssertEqual(DatasetExporter.cell("-2.5"), "\"-2.5\"")
    }
    func testVerifiedExportExcludesEarlierPlansAndSuggestions() throws {
        var project = ReviewProject(); var doc = source(); doc.pages[0].text += "\nnew verified"; project.documents = [doc]; project.plan.version = 2
        project.observations = [
            .init(documentID: doc.id, variableID: "title", value: "old verified", status: .verified, planVersion: 1),
            .init(documentID: doc.id, variableID: "title", value: "new suggestion", planVersion: 2),
            .init(documentID: doc.id, variableID: "title", value: "new verified", status: .verified, planVersion: 2)
        ]
        project.observations[2].citations = [.init(page: 1, quote: "new verified")]
        project.observations[2] = try ReviewEngine.verify(project.observations[2], variable: project.plan.variables.first { $0.id == "title" }!, reviewer: "QA", document: doc)
        let csv = DatasetExporter.longCSV(project, verifiedOnly: true)
        XCTAssertTrue(csv.contains("new verified")); XCTAssertFalse(csv.contains("old verified")); XCTAssertFalse(csv.contains("new suggestion"))
    }
    func testReviewedValuesSurviveReextractionAndOtherReportsStayUntouched() {
        let doc = UUID(); let otherDoc = UUID()
        let protected = Observation(documentID: doc, variableID: "age_mean", value: "68.5", status: .verified)
        let other = Observation(documentID: otherDoc, variableID: "age_mean", value: "42")
        let replacement = Observation(documentID: doc, variableID: "age_mean", value: "99")
        let extra = Observation(documentID: doc, variableID: "events", value: "0")
        let merged = ReviewEngine.mergeSuggestions(existing: [protected, other], incoming: [replacement, extra], documentID: doc, planVersion: 1)
        XCTAssertEqual(merged.count, 3); XCTAssertTrue(merged.contains(protected)); XCTAssertTrue(merged.contains(other)); XCTAssertFalse(merged.contains(replacement))
    }
    func testAbsenceRowsSkipVariablesTheReviewerAlreadyRecorded() {
        let doc = UUID()
        let variables = [field("n", type: .integer), field("events", type: .integer), field("age_mean")]
        let verified = Observation(documentID: doc, variableID: "n", value: "235", context: .init(arm: "Control"), status: .verified, reviewer: "QA")
        let rejected = Observation(documentID: doc, variableID: "age_mean", value: "99", status: .rejected, reviewer: "QA")
        let fromThisRun = Observation(documentID: doc, variableID: "events", value: "4", model: "m")
        let rows = ReviewEngine.absenceSuggestions(variables: variables, consolidated: [fromThisRun], existing: [verified, rejected], documentID: doc, pagesIncomplete: false, model: "m", planVersion: 1)
        XCTAssertEqual(rows.map(\.variableID), ["age_mean"], "A reviewer-recorded value is not absence; a rejected suggestion still needs an explicit absence decision.")
        XCTAssertEqual(rows.first?.missingness, .notReported)
        XCTAssertEqual(ReviewEngine.absenceSuggestions(variables: variables, consolidated: [], existing: [], documentID: doc, pagesIncomplete: true, model: "m", planVersion: 1).map(\.missingness), [.unclear, .unclear, .unclear])
    }
    func testHistoricalExportKeepsHistoricalUnits() {
        var project = ReviewProject(); let doc = source(); project.documents = [doc]
        var oldPlan = project.plan; oldPlan.variables[0].unit = "old-units"
        project.planHistory = [.init(date: Date(), reason: "Unit changed", plan: oldPlan)]
        project.plan.version = 2; project.plan.variables[0].unit = "new-units"
        project.observations = [.init(documentID: doc.id, variableID: "title", value: "historical", planVersion: 1)]
        let csv = DatasetExporter.longCSV(project, verifiedOnly: false)
        XCTAssertTrue(csv.contains("old-units")); XCTAssertFalse(csv.contains("new-units"))
    }
    func testNegativeEventCountsRejectedButNegativeEffectsAllowed() {
        let doc = source()
        let negativeCount = Observation(documentID: doc.id, variableID: "events", value: "-1")
        XCTAssertThrowsError(try ReviewEngine.validateObservationValue(negativeCount, variable: .init(id: "events", label: "Events", definition: "Event count", type: .integer)))
        let effect = Observation(documentID: doc.id, variableID: "effect_estimate", value: "-1.2")
        XCTAssertNoThrow(try ReviewEngine.validateObservationValue(effect, variable: .init(id: "effect_estimate", label: "Effect", definition: "Mean difference", type: .number)))
    }
}
