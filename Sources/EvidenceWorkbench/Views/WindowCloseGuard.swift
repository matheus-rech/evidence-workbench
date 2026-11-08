import SwiftUI
import AppKit

/// Keep native close actions from silently discarding a local editor draft.
struct WindowCloseGuard: NSViewRepresentable {
    var store: WorkspaceStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.didAttach = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }
        return view
    }
    func updateNSView(_ nsView: ObserverView, context: Context) {
        if let window = nsView.window { context.coordinator.attach(window) }
    }
    final class ObserverView: NSView {
        var didAttach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { didAttach?(window) } }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        let store: WorkspaceStore
        weak var previous: NSWindowDelegate?
        init(store: WorkspaceStore) { self.store = store }
        func attach(_ window: NSWindow) {
            guard window.delegate !== self else { return }
            previous = window.delegate; window.delegate = self
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if store.hasUnsavedChanges || store.busy {
                let alert = NSAlert(); alert.messageText = "Save your review edits first"
                alert.informativeText = "Save or discard your editor changes and finish or cancel the active operation before closing this window."
                alert.addButton(withTitle: "Keep working"); alert.runModal()
                return false
            }
            return previous?.windowShouldClose?(sender) ?? true
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (previous?.responds(to: selector) ?? false) }
        override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector) }
    }
}
