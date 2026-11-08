import SwiftUI
import AppKit

@main struct EvidenceWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WorkspaceStore()
    var body: some Scene {
        WindowGroup(Bundle.main.bundleIdentifier?.hasSuffix(".QA") == true ? "Evidence Workbench — QA TEST COPY" : "Evidence Workbench", id: "workspace") {
            ContentView(store: store)
                .frame(minWidth: 1080, minHeight: 720)
                .background(WindowCloseGuard(store: store).frame(width: 0, height: 0))
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1460, height: 940)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Review", action: store.newProject).keyboardShortcut("n").disabled(store.busy || store.hasUnsavedChanges)
                Button("Restore Review Backup…") { FilePanels.restore(store) }.disabled(store.busy || store.hasUnsavedChanges)
            }
            CommandMenu("Review") {
                Button("Import Protocol…") { FilePanels.importFiles(store, protocolOnly: true) }.keyboardShortcut("p", modifiers: [.command, .shift]).disabled(store.current == nil || store.busy)
                Button("Import Articles…") { FilePanels.importFiles(store, protocolOnly: false) }.keyboardShortcut("i").disabled(store.current?.plan.readyForArticles != true || store.busy || store.hasUnsavedChanges)
                Divider()
                Button("Export Verified Dataset…") { FilePanels.exportCSV(store, verifiedOnly: true) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(store.current == nil || store.busy)
                Button("Back Up Review…") { FilePanels.backup(store) }.disabled(store.current == nil || store.busy || store.hasUnsavedChanges)
            }
        }
        Settings { SettingsView().frame(width: 570) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.hasUnsavedChanges == true || store?.busy == true else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "Review work has not been saved"
        alert.informativeText = "Save or discard your editor changes and finish or cancel the active operation before quitting."
        alert.addButton(withTitle: "Keep working")
        alert.runModal()
        return .terminateCancel
    }
}
