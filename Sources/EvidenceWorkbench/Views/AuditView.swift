import SwiftUI
import ReviewCore

struct AuditView: View {
    var project: ReviewProject
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audit trail").font(.largeTitle.weight(.bold))
            Text("Saved plan decisions, imports, edits, verification and research activity. The local log supports review and reproducibility; it is not a tamper-proof regulatory audit system.").foregroundStyle(.secondary)
            TextField("Search decisions, reviewers and changes", text: $query).textFieldStyle(.roundedBorder)
            List {
                ForEach(project.audit.reversed().filter { query.isEmpty || [$0.action, $0.actor, $0.detail].joined(separator: " ").localizedCaseInsensitiveContains(query) }) { event in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(event.action).font(.headline); Spacer(); Text(event.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                        Text(event.actor.isEmpty ? "Reviewer not named" : event.actor).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(event.detail).font(.callout).textSelection(.enabled)
                    }.padding(.vertical, 8)
                }
            }
        }.padding(24)
    }
}
