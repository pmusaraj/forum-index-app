#if os(macOS)
import SwiftUI

struct MacKeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading") {
                    shortcut("Previous topic", keys: "↑")
                    shortcut("Next topic", keys: "↓")
                    shortcut("Star or unstar topic", keys: "S")
                    shortcut("Previous subject", keys: "⌘ ↑")
                    shortcut("Next subject", keys: "⌘ ↓")
                    shortcut("Scroll Markdown down a page", keys: "Space")
                    shortcut("Scroll Markdown up a page", keys: "⇧ Space")
                    Text("If no topic is selected, either arrow selects the first topic.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("App") {
                    shortcut("Toggle sidebar", keys: "⌃ ⌘ S")
                    shortcut("Refresh topics", keys: "⌘ R")
                    shortcut("Settings", keys: "⌘ ,")
                    shortcut("Keyboard shortcuts", keys: "?")
                    shortcut("Close this sheet", keys: "Esc")
                }
                Section("Windows") {
                    shortcut("New window", keys: "⌘ N")
                    shortcut("Close window", keys: "⌘ W")
                    shortcut("Quit Forum Index", keys: "⌘ Q")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 460, height: 600)
    }

    private func shortcut(_ title: String, keys: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
