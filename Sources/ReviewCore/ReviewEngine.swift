import Foundation

public enum ReviewEngine {
    /// Preserve malformed model rows for correction without discarding other valid evidence.
    /// Unknown document/variable references still fail closed.
    public static func reviewableSuggestion(_ observation: Observation, variable: VariableDefinition, document: SourceDocument) throws -> Observation {
        guard observation.documentID == document.id, observation.variableID == variable.id else { throw WorkbenchError.invalid("Extraction references an unknown document or variable.") }
        do { return try validated(observation, variable: variable, document: document) }
        catch {
            var flagged = observation
            flagged.value = ""; flagged.missingness = .unclear; flagged.confidence = nil
            flagged.citations = observation.citations.filter { citation in document.pages.contains { $0.number == citation.page } }
            flagged.note = "Invalid model suggestion retained for correction. Raw value: \(observation.value.prefix(1_000)). Validation: \(error.localizedDescription). " + observation.note
            return try validated(flagged, variable: variable, document: document)
        }
    }

    public static func normalizeQuote(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func validated(_ observation: Observation, variable: VariableDefinition, document: SourceDocument) throws -> Observation {
        guard observation.documentID == document.id, observation.variableID == variable.id else { throw WorkbenchError.invalid("Extraction references an unknown document or variable.") }
        if let score = observation.confidence, !(0...100).contains(score) { throw WorkbenchError.invalid("Confidence must be an integer from 0 to 100.") }
        try validateObservationValue(observation, variable: variable)
        var checked = observation
        checked.status = .suggested
        checked.reviewer = ""
        checked.citations = try observation.citations.map { citation in
            guard let page = document.pages.first(where: { $0.number == citation.page }) else { throw WorkbenchError.invalid("A source citation references an unavailable page.") }
            var result = citation
            if let region = citation.region, !region.isValid { throw WorkbenchError.invalid("The source region is outside the PDF page.") }
            result.visuallyVerified = nil
            let range = QuoteLocator.resolve(in: page.text, quote: citation.quote, start: citation.startUTF16, length: citation.lengthUTF16)
            result.exactMatch = range != nil
            result.startUTF16 = range?.location; result.lengthUTF16 = range?.length
            return result
        }
        return checked
    }

    public static func validateValue(_ value: String, missingness: Missingness, type: FieldType) throws {
        if missingness != .reported {
            guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkbenchError.invalid("Missing data must have an empty value; choose ‘reported’ for observed values.") }
            return
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkbenchError.invalid("Reported values cannot be empty.") }
        switch type {
        case .text: break
        case .number:
            guard let number = Double(value), number.isFinite else { throw WorkbenchError.invalid("Enter a finite numeric value with a decimal point, without units or thousands separators.") }
        case .integer:
            guard Int(value) != nil else { throw WorkbenchError.invalid("Enter an integer without units or thousands separators.") }
        case .date:
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { throw WorkbenchError.invalid("Enter a real calendar date as YYYY-MM-DD.") }
        case .yesNo:
            guard ["Yes", "No"].contains(value) else { throw WorkbenchError.invalid("Choose Yes or No, or record missingness separately.") }
        }
    }

    public static func validateObservationValue(_ observation: Observation, variable: VariableDefinition) throws {
        try validateValue(observation.value, missingness: observation.missingness, type: variable.type)
        if observation.missingness == .reported, ["outcome_mean", "outcome_sd"].contains(variable.id) {
            let context = [observation.context.outcome, observation.context.analysis, observation.note].joined(separator: " ").lowercased()
            if context.range(of: "\\b(proportion|percentage|incidence rate|event rate)\\b|per\\s+1[, ]?000", options: .regularExpression) != nil {
                throw WorkbenchError.invalid("This mean/SD observation is labeled as a proportion, percentage or rate. Use the matching outcome field or clarify its continuous-outcome context before verification.")
            }
        }
        if observation.missingness == .reported, ["n", "events", "age_mean", "age_sd", "age_median", "outcome_sd"].contains(variable.id), let number = Double(observation.value), number < 0 { throw WorkbenchError.invalid("Counts, ages and standard deviations cannot be negative.") }
    }

    public static func edited(_ observation: Observation, value: String, missingness: Missingness, context: ObservationContext, note: String) -> Observation {
        var copy = observation
        let valueChanged = copy.value != value || copy.missingness != missingness || copy.context != context
        copy.value = value; copy.missingness = missingness; copy.context = context; copy.note = note
        copy.status = .edited; copy.confidence = nil; copy.reviewer = ""; copy.updatedAt = Date()
        if valueChanged { copy.citations = [] }
        if valueChanged || note != observation.note { copy.sourceCheck = nil; copy.sourceAdjudication = nil }
        return copy
    }

    public static func verify(_ observation: Observation, variable: VariableDefinition, reviewer: String, document: SourceDocument) throws -> Observation {
        guard !reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkbenchError.invalid("A named reviewer is required for verification.") }
        try validateObservationValue(observation, variable: variable)
        guard SourceCheckPolicy.resolved(observation) else { throw WorkbenchError.invalid("The AI value needs a supporting independent source check or an explicit reviewer adjudication explaining the disagreement. A matching quotation alone is insufficient.") }
        var copy = observation
        copy.citations = try observation.citations.map { citation in
            guard let page = document.pages.first(where: { $0.number == citation.page }) else { throw WorkbenchError.invalid("The cited page does not exist.") }
            if let region = citation.region {
                guard region.isValid, citation.visuallyVerified == true, !citation.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkbenchError.invalid("Image evidence requires a valid page region, a transcription and explicit visual checking of the value, units and context.") }
                var visual = citation; visual.exactMatch = false; visual.startUTF16 = nil; visual.lengthUTF16 = nil
                return visual
            }
            guard let range = QuoteLocator.resolve(in: page.text, quote: citation.quote, start: citation.startUTF16, length: citation.lengthUTF16) else { throw WorkbenchError.invalid("The source quote is missing, ambiguous, or its saved location changed. Select the exact occurrence on the cited PDF page; no partial match will be substituted.") }
            return EvidenceCitation(page: citation.page, quote: citation.quote, exactMatch: true, startUTF16: range.location, lengthUTF16: range.length)
        }
        if observation.missingness == .reported && copy.citations.isEmpty { throw WorkbenchError.invalid("Reported values need an exact page quotation or a visually checked PDF region before verification.") }
        if observation.missingness != .reported && observation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw WorkbenchError.invalid("Explain the missingness decision in the reviewer note.") }
        copy.status = .verified; copy.reviewer = reviewer; copy.updatedAt = Date()
        return copy
    }

    public static func extractionChunks(_ pages: [DocumentPage], limit: Int = 28_000) -> [[DocumentPage]] {
        precondition(limit > 0)
        var chunks: [[DocumentPage]] = []; var current: [DocumentPage] = []; var size = 0
        for page in pages {
            var remaining = page.text[...]
            repeat {
                let segment = String(remaining.prefix(limit))
                if size + segment.count > limit && !current.isEmpty { chunks.append(current); current = []; size = 0 }
                current.append(DocumentPage(number: page.number, text: segment, ocr: page.ocr)); size += segment.count
                remaining = remaining.dropFirst(segment.count)
            } while !remaining.isEmpty
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    public static func consolidate(_ values: [Observation]) -> [Observation] {
        var result: [Observation] = []
        for value in values {
            // Repeated text across overlapping contexts stays distinct if context/value differs.
            if let index = result.firstIndex(where: { $0.documentID == value.documentID && $0.variableID == value.variableID && $0.context == value.context && $0.value == value.value && $0.missingness == value.missingness }) {
                for citation in value.citations where !result[index].citations.contains(citation) { result[index].citations.append(citation) }
            } else { result.append(value) }
        }
        return result.filter { value in
            value.missingness == .reported || !result.contains { $0.documentID == value.documentID && $0.variableID == value.variableID && $0.context == value.context && $0.missingness == .reported }
        }
    }

    public static func mergeSuggestions(existing: [Observation], incoming: [Observation], documentID: UUID, planVersion: Int) -> [Observation] {
        let protected = existing.filter { $0.documentID == documentID && $0.status != .suggested }
        let accepted = incoming.filter { row in
            row.documentID == documentID && row.planVersion == planVersion && !protected.contains { $0.variableID == row.variableID && $0.context == row.context }
        }
        return existing.filter { !($0.documentID == documentID && $0.status == .suggested && $0.planVersion == planVersion) } + accepted
    }
}
