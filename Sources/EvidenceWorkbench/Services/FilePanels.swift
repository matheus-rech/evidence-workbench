import AppKit
import UniformTypeIdentifiers

@MainActor enum FilePanels {
    static func importFiles(_ store: WorkspaceStore, protocolOnly: Bool) {
        guard !store.busy else { return }
        guard !store.hasUnsavedObservation else { store.errorMessage = "Save or discard observation edits before importing documents."; return }
        let panel = NSOpenPanel()
        panel.title = protocolOnly ? "Import review protocol" : "Import article reports"
        panel.message = protocolOnly ? "PROSPERO and other protocols can be imported before article upload. PDF, DOCX, TXT or Markdown." : "Original reports stay local. AI extraction sends their page text only when you request it. Peer-review status must be checked by a reviewer."
        panel.allowedContentTypes = [.pdf, .plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "docx") ?? .data]
        panel.allowsMultipleSelection = !protocolOnly
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { store.importDocuments(panel.urls, protocolOnly: protocolOnly) }
    }
    static func exportCSV(_ store: WorkspaceStore, verifiedOnly: Bool) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = verifiedOnly ? "verified_observations.csv" : "all_observations_with_provenance.csv"
        panel.message = verifiedOnly ? "Only human-verified observations from the current plan version are included. The export is long-format; join arms and outcomes deliberately before meta-analysis." : "Includes unverified, rejected and earlier-plan rows with explicit status and source quotes."
        if panel.runModal() == .OK, let url = panel.url { store.exportCSV(to: url, verifiedOnly: verifiedOnly) }
    }
    static func backup(_ store: WorkspaceStore) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Review-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).reviewbundle"
        panel.message = "Creates a new folder containing the saved review and source files. Choose an unused name."
        if panel.runModal() == .OK, let url = panel.url { store.exportBackup(to: url) }
    }
    static func restore(_ store: WorkspaceStore) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true; panel.message = "Choose an exported review folder. Restoration creates a separate review and verifies source-file hashes."
        if panel.runModal() == .OK, let url = panel.url { store.restoreBackup(from: url) }
    }
}
