import Foundation

public enum DatasetExporter {
    public static func cell(_ value: String) -> String {
        let dangerous = value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
        // Preserve actual numeric negatives; neutralize text interpreted as spreadsheet formulas.
        let numeric = Double(value).map(\.isFinite) == true
        let safe = dangerous && !numeric ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    public static func longCSV(_ project: ReviewProject, verifiedOnly: Bool, aiReviewedOnly: Bool = false) -> String {
        let headers = ["review_id", "study_id", "report_id", "report_filename", "source_sha256", "peer_review_status", "variable_id", "variable_label", "variable_type", "unit", "scope", "arm", "comparator", "outcome", "timepoint", "subgroup", "analysis", "value", "missingness", "review_status", "reviewer", "model_confidence_unvalidated", "source_pages", "source_quotes", "source_start_utf16", "source_length_utf16", "source_regions_normalized", "visual_source_checked", "quotes_match", "reviewer_note", "model", "plan_version", "current_plan_version", "updated_at", "ai_source_check", "ai_source_check_reason", "ai_source_check_model", "ai_source_check_fresh", "source_adjudication"]
        let iso = ISO8601DateFormatter()
        let observations = project.observations.filter { (!verifiedOnly || VerificationPolicy.exportable($0, project: project)) && (!aiReviewedOnly || VerificationPolicy.exportable($0, project: project, automated: true)) }
        let rows: [[String]] = observations.compactMap { item in
            guard let document = project.documents.first(where: { $0.id == item.documentID }) else { return nil }
            let definition = item.planVersion == project.plan.version
                ? project.plan.variables.first { $0.id == item.variableID }
                : project.planHistory.first { $0.plan.version == item.planVersion }?.plan.variables.first { $0.id == item.variableID }
            return [project.id.uuidString, document.studyID.uuidString, document.id.uuidString, document.filename, document.sha256, document.peerReviewStatus, item.variableID, definition?.label ?? "Archived variable", definition?.type.rawValue ?? "", definition?.unit ?? "", definition?.scope.rawValue ?? "", item.context.arm, item.context.comparator, item.context.outcome, item.context.timepoint, item.context.subgroup, item.context.analysis, item.value, item.missingness.rawValue, item.status.rawValue, item.reviewer, item.confidence.map(String.init) ?? "", item.citations.map { String($0.page) }.joined(separator: " | "), item.citations.map(\.quote).joined(separator: " | "), item.citations.map { $0.startUTF16.map(String.init) ?? "" }.joined(separator: " | "), item.citations.map { $0.lengthUTF16.map(String.init) ?? "" }.joined(separator: " | "), item.citations.map { citation in citation.region.map { "x=\($0.x);y=\($0.y);width=\($0.width);height=\($0.height)" } ?? "" }.joined(separator: " | "), item.citations.map { $0.visuallyVerified == true ? "true" : "false" }.joined(separator: " | "), item.citations.allSatisfy(\.exactMatch) && !item.citations.isEmpty ? "true" : "false", item.note, item.model, String(item.planVersion), String(project.plan.version), iso.string(from: item.updatedAt), item.sourceCheck?.verdict.rawValue ?? "pending", item.sourceCheck?.reason ?? "", item.sourceCheck?.model ?? "", definition.map { SourceCheckPolicy.fresh(item, variable: $0, document: document) } == true ? "true" : "false", item.sourceAdjudication ?? ""]
        }
        return ([headers] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
