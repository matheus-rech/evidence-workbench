import XCTest
import ReviewCore
@testable import EvidenceWorkbench

/// Paid, opt-in end-to-end check of the extraction pipeline against the pilot's hand-checked cells.
///
/// Runs only when all of these are set; otherwise it is skipped and makes no network call:
/// - `EW_LIVE_EXTRACTION_PDF`: path to Arts et al. 2017 (PLoS One 12:e0170974), the pilot report.
/// - `EW_LIVE_KEY_FILE`: path to an env file holding `OPENAI_API_KEY` (read with `LocalKeyFile`, never printed).
/// - `EW_LIVE_REPORT`: path where the JSON scoring report is written.
/// Optional: `EW_LIVE_MODEL` (default gpt-4.1) and `EW_LIVE_CHECK_MODEL` (default: same as the model).
///
/// It uses the same steps the app uses (DocumentLoader, PDFPageImages, OpenAIClient.extract, ReviewEngine
/// quarantine/consolidation, OpenAIClient.checkSources), but not the SwiftUI store or Keychain.
@MainActor
final class LiveExtractionTests: XCTestCase {
    /// Table 1, physical PDF page 7, as recorded in docs/REAL_WORLD_PILOT.md.
    private struct Cell: Encodable { let variable: String; let arm: String; let time: String; let value: Double }
    private let truth: [Cell] = [
        .init(variable: "n", arm: "control", time: "baseline", value: 235), .init(variable: "n", arm: "intervention", time: "baseline", value: 496),
        .init(variable: "n", arm: "control", time: "post", value: 259), .init(variable: "n", arm: "intervention", time: "post", value: 522),
        .init(variable: "age_mean", arm: "control", time: "baseline", value: 74.61), .init(variable: "age_sd", arm: "control", time: "baseline", value: 13.63),
        .init(variable: "age_mean", arm: "intervention", time: "baseline", value: 72.13), .init(variable: "age_sd", arm: "intervention", time: "baseline", value: 12.46),
        .init(variable: "age_mean", arm: "control", time: "post", value: 73.73), .init(variable: "age_sd", arm: "control", time: "post", value: 14.7),
        .init(variable: "age_mean", arm: "intervention", time: "post", value: 72.79), .init(variable: "age_sd", arm: "intervention", time: "post", value: 12.61)
    ]
    private struct Row: Encodable { let variable: String; let value: String; let context: String; let page: Int; let quoteAnchored: Bool; let quarantined: Bool; let verdict: String; let matchesTruth: Bool }
    private struct Report: Encodable {
        let model: String; let checkModel: String; let page: Int; let truthCells: Int; let matched: Int
        let missed: [Cell]; let rows: [Row]
        let reportedRows: Int; let unmatchedReportedRows: Int
        let supportedAmongMatched: Int; let supportedAmongUnmatched: Int
    }

    private func env(_ key: String) -> String? { ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 } }

    /// Each label is read from its own field, so a comparator or a note cannot change which cell a row is scored against.
    static func time(_ label: String) -> String? {
        let text = label.lowercased()
        let baseline = text.contains("baseline") || text.contains("pre-")
        let post = text.contains("post") || text.contains("follow") || text.contains("end of study")
        return baseline == post ? nil : (baseline ? "baseline" : "post")
    }
    static func arm(_ label: String) -> String? {
        let text = label.lowercased()
        let control = text.contains("control") || text.contains("usual care")
        let intervention = text.contains("intervention")
        return control == intervention ? nil : (control ? "control" : "intervention")
    }
    /// Arm from `context.arm`; time from `context.timepoint`, falling back to `context.analysis` only when the time point is empty.
    static func matches(_ row: Observation, variable: String, arm cellArm: String, time cellTime: String, value cellValue: Double) -> Bool {
        guard row.missingness == .reported, row.variableID == variable, let value = Double(row.value) else { return false }
        let timeLabel = row.context.timepoint.trimmingCharacters(in: .whitespaces).isEmpty ? row.context.analysis : row.context.timepoint
        return abs(value - cellValue) < 1e-9 && arm(row.context.arm) == cellArm && time(timeLabel) == cellTime
    }

    /// Free, always-run check of the scorer, so the paid test cannot report a false 12/12 or a false miss.
    func testScorerReadsArmAndTimeFromTheirOwnFields() {
        let doc = UUID()
        func row(_ value: String, arm: String, comparator: String = "", time: String, analysis: String = "", note: String = "") -> Observation {
            Observation(documentID: doc, variableID: "age_mean", value: value, context: .init(arm: arm, comparator: comparator, timepoint: time, analysis: analysis), note: note)
        }
        XCTAssertTrue(Self.matches(row("72.13", arm: "Intervention", comparator: "Control", time: "Baseline"), variable: "age_mean", arm: "intervention", time: "baseline", value: 72.13), "A comparator naming the other arm must not reject the row.")
        XCTAssertTrue(Self.matches(row("73.73", arm: "Control", comparator: "vs baseline", time: "Post-study"), variable: "age_mean", arm: "control", time: "post", value: 73.73), "A comparator naming another time must not move the row.")
        XCTAssertFalse(Self.matches(row("73.73", arm: "Control", time: "Post-study"), variable: "age_mean", arm: "control", time: "baseline", value: 73.73))
        XCTAssertFalse(Self.matches(row("73.73", arm: "Control", time: "Post-study", note: "baseline value"), variable: "age_mean", arm: "control", time: "baseline", value: 73.73), "A note must not change the time point.")
        XCTAssertTrue(Self.matches(row("74.61", arm: "Control", time: "", analysis: "Baseline characteristics"), variable: "age_mean", arm: "control", time: "baseline", value: 74.61), "An empty time point falls back to the analysis label.")
        XCTAssertFalse(Self.matches(row("74.61", arm: "Control and intervention", time: "Baseline"), variable: "age_mean", arm: "control", time: "baseline", value: 74.61), "A row naming both arms is not a single-arm cell.")
        XCTAssertFalse(Self.matches(row("74.6", arm: "Control", time: "Baseline"), variable: "age_mean", arm: "control", time: "baseline", value: 74.61))
    }

    func testArtsTableOneMatchesHandCheckedCells() async throws {
        guard let pdfPath = env("EW_LIVE_EXTRACTION_PDF"), let keyPath = env("EW_LIVE_KEY_FILE"), let reportPath = env("EW_LIVE_REPORT") else {
            throw XCTSkip("Live extraction is opt-in: set EW_LIVE_EXTRACTION_PDF, EW_LIVE_KEY_FILE and EW_LIVE_REPORT.")
        }
        let model = env("EW_LIVE_MODEL") ?? "gpt-4.1"
        let checkModel = env("EW_LIVE_CHECK_MODEL") ?? model
        let key = try LocalKeyFile.read(URL(fileURLWithPath: keyPath))
        let pdf = URL(fileURLWithPath: pdfPath)
        let pageNumber = 7

        let loaded = try await DocumentLoader.load(pdf, ocr: false)
        let document = SourceDocument(filename: pdf.lastPathComponent, relativePath: "documents/live.pdf", sha256: "live", pages: loaded.pages)
        let page = try XCTUnwrap(document.pages.first { $0.number == pageNumber })
        let variables = try ["n", "age_mean", "age_sd"].map { id in try XCTUnwrap(CoreFields.defaults.first { $0.id == id }) }
        var plan = ReviewPlan()
        plan.researchQuestion = "Effect of a clinical decision support system on anticoagulant prescribing in atrial fibrillation."
        plan.variables = variables

        let client = OpenAIClient()
        let images = try await PDFPageImages.render(url: pdf, pageNumbers: [pageNumber])
        let extraction = try await client.extract(pages: [page], variables: variables, plan: plan, model: model, apiKey: key, pageImages: images)

        var staged: [Observation] = []
        for row in extraction.observations where row.missingness != .notReported {
            let field = try XCTUnwrap(variables.first { $0.id == row.variable_id }, "The model returned a variable outside the batch.")
            let observation = Observation(documentID: document.id, variableID: row.variable_id, value: row.value, missingness: row.missingness, context: .init(arm: row.arm, comparator: row.comparator, outcome: row.outcome, timepoint: row.timepoint, subgroup: row.subgroup, analysis: row.analysis), citations: row.quote.isEmpty ? [] : [EvidenceCitation(page: row.page, quote: row.quote)], confidence: row.confidence, note: row.note, model: model)
            staged.append(try ReviewEngine.reviewableSuggestion(observation, variable: field, document: document))
        }
        var rows = ReviewEngine.consolidate(staged)
        let reported = rows.indices.filter { rows[$0].missingness == .reported }
        for start in stride(from: 0, to: reported.count, by: 8) {
            let batch = Array(reported[start..<min(start + 8, reported.count)])
            let checks = try await client.checkSources(observations: batch.map { rows[$0] }, variables: variables, pages: [page], images: images, model: checkModel, apiKey: key)
            for index in batch { if let check = checks.checks.first(where: { $0.observation_id == rows[index].id }) { rows[index].sourceCheck = .init(verdict: check.verdict, reason: check.reason, quote: check.source_quote, model: checkModel, claimFingerprint: SourceCheckPolicy.fingerprint(rows[index])) } }
        }

        func matches(_ row: Observation, _ cell: Cell) -> Bool { Self.matches(row, variable: cell.variable, arm: cell.arm, time: cell.time, value: cell.value) }
        let missed = truth.filter { cell in !rows.contains { matches($0, cell) } }
        let reportRows = rows.map { row in
            Row(variable: row.variableID, value: row.value, context: row.context.summary, page: row.citations.first?.page ?? 0, quoteAnchored: row.citations.first?.exactMatch ?? false, quarantined: row.note.hasPrefix("Invalid model suggestion"), verdict: row.sourceCheck?.verdict.rawValue ?? "none", matchesTruth: truth.contains { matches(row, $0) })
        }
        let reportedRows = reportRows.filter { !$0.value.isEmpty }
        let report = Report(model: model, checkModel: checkModel, page: pageNumber, truthCells: truth.count, matched: truth.count - missed.count, missed: missed, rows: reportRows,
                            reportedRows: reportedRows.count, unmatchedReportedRows: reportedRows.filter { !$0.matchesTruth }.count,
                            supportedAmongMatched: reportedRows.filter { $0.matchesTruth && $0.verdict == "supported" }.count,
                            supportedAmongUnmatched: reportedRows.filter { !$0.matchesTruth && $0.verdict == "supported" }.count)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: reportPath))

        // Pipeline invariants: these must hold whatever the model returns.
        XCTAssertFalse(rows.isEmpty, "The model returned no rows for a page that holds a populated Table 1.")
        for row in rows where row.missingness == .reported {
            XCTAssertTrue(row.citations.allSatisfy { $0.page == pageNumber }, "A citation names a page that was not supplied.")
            XCTAssertNotNil(row.sourceCheck, "Every reported row must receive a source-check verdict.")
            XCTAssertEqual(row.status, .suggested, "Nothing may arrive verified.")
        }
        // Accuracy is recorded in the report rather than asserted, because model output varies run to run.
    }
}
