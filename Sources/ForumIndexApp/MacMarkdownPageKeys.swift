#if os(macOS)
import AppKit
import SwiftUI

/// Selectable Markdown text can consume Space before SwiftUI menu shortcuts run.
/// Handle paging for the active reader without stealing input from editors or sheets.
struct MacMarkdownPageKeys: NSViewRepresentable {
    let isActive: Bool
    let scroll: (Int) -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.isActive = isActive
        view.scroll = scroll
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.isActive = isActive
        nsView.scroll = scroll
    }

    static func dismantleNSView(_ nsView: KeyView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class KeyView: NSView {
        var isActive = false
        var scroll: (Int) -> Void = { _ in }
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handle(event) == nil
                }
                return handled ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isActive, let window, window.isKeyWindow,
                  event.window === window, window.attachedSheet == nil,
                  event.charactersIgnoringModifiers == " " else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard modifiers.isEmpty || modifiers == .shift else { return event }
            if let editor = window.firstResponder as? NSTextView, editor.isEditable { return event }
            scroll(modifiers == .shift ? -1 : 1)
            return nil
        }
    }
}
#endif
