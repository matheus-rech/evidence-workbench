import Foundation

public enum VerificationPolicy {
    public static func exportable(_ row: Observation, project: ReviewProject, automated: Bool = false) -> Bool {
        guard row.status == (automated ? .aiReviewed : .verified), row.planVersion == project.plan.version,
              let document = project.documents.first(where: { $0.id == row.documentID }),
              let variable = project.plan.variables.first(where: { $0.id == row.variableID }),
              !row.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              row.verificationFingerprint == SourceCheckPolicy.evidenceFingerprint(row, variable: variable, document: document) else { return false }
        if automated { return AutomationPolicy.isAcceptable(row, variable: variable, document: document) }
        return (try? ReviewEngine.verify(row, variable: variable, reviewer: row.reviewer, document: document)) != nil
    }
    /// Reject broken references; preserve legacy/untrusted verification as an editable value with an audit warning.
    public static func validate(_ original: ReviewProject) throws -> ReviewProject {
        var project = original
        let documents = project.documents + project.protocols
        guard Set(documents.map(\.id)).count == documents.count,
              Set(project.observations.map(\.id)).count == project.observations.count,
              Set(project.planHistory.map { $0.plan.version }).count == project.planHistory.count else { throw WorkbenchError.invalid("Duplicate report, observation or plan-history identities.") }
        for document in documents {
            guard Set(document.pages.map(\.number)).count == document.pages.count,
                  document.pages.allSatisfy({ $0.number > 0 }) else { throw WorkbenchError.invalid("Source pages have duplicate or invalid numbers.") }
        }
        for index in project.observations.indices {
            let row = project.observations[index]
            guard project.documents.contains(where: { $0.id == row.documentID }) else { throw WorkbenchError.invalid("An observation references a missing report.") }
            let plan = row.planVersion == project.plan.version ? project.plan : project.planHistory.first { $0.plan.version == row.planVersion }?.plan
            guard let plan, plan.variables.contains(where: { $0.id == row.variableID }) else { throw WorkbenchError.invalid("An observation references an unknown field or plan version.") }
            if row.status == .verified || row.status == .aiReviewed {
                // Historical decisions are checked against the historical field dictionary, not silently re-versioned.
                var snapshot = project; snapshot.plan = plan
                if !exportable(row, project: snapshot, automated: row.status == .aiReviewed) {
                    project.observations[index].status = .edited
                    project.observations[index].verificationFingerprint = nil
                    project.audit.append(.init(actor: "Integrity check", action: "Verification quarantined", detail: "\(row.id): retained value and prior reviewer \(row.reviewer); source/definition-bound verification is missing or invalid. Review again before export."))
                }
            }
        }
        return project
    }
}

public enum AutomationPolicy {
    /// Machine review never claims human verification. Unanchored/contradicted rows remain suggestions.
    public static func isAcceptable(_ row: Observation, variable: VariableDefinition, document: SourceDocument) -> Bool {
        guard row.missingness == .reported, row.documentID == document.id, row.variableID == variable.id,
              SourceCheckPolicy.supported(row, variable: variable, document: document),
              !row.citations.isEmpty,
              row.citations.allSatisfy({ citation in
                  citation.region == nil && document.pages.contains { page in
                      page.number == citation.page && !page.ocr && QuoteLocator.resolve(in: page.text, quote: citation.quote, start: citation.startUTF16, length: citation.lengthUTF16) != nil
                  }
              }), (try? ReviewEngine.validateObservationValue(row, variable: variable)) != nil else { return false }
        if variable.type == .number || variable.type == .integer {
            return row.citations.contains { !ProvenanceValueLocator.ranges(value: row.value, quote: $0.quote, numeric: true).isEmpty }
        }
        return true
    }
    public static func review(_ row: Observation, variable: VariableDefinition, document: SourceDocument) -> Observation {
        guard row.status == .suggested, isAcceptable(row, variable: variable, document: document) else { return row }
        var reviewed = row; reviewed.status = .aiReviewed; reviewed.reviewer = "AI: " + (row.sourceCheck?.model ?? row.model)
        reviewed.verificationFingerprint = SourceCheckPolicy.evidenceFingerprint(reviewed, variable: variable, document: document)
        reviewed.updatedAt = Date(); return reviewed
    }
}
