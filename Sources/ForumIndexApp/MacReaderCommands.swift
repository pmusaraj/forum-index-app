#if os(macOS)
import SwiftUI

struct MacReaderCommands: Commands {
    @FocusedValue(\.readerNavigation) private var navigation
    @FocusedValue(\.markdownScroll) private var markdownScroll
    @FocusedValue(\.topicStar) private var topicStar

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Previous Topic") { navigation?.moveTopic(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(navigation == nil)
            Button("Next Topic") { navigation?.moveTopic(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(navigation == nil)
            Divider()
            Button("Scroll Down a Page") { markdownScroll?.scroll(1) }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(navigation == nil || markdownScroll == nil)
            Button("Scroll Up a Page") { markdownScroll?.scroll(-1) }
                .keyboardShortcut(.space, modifiers: .shift)
                .disabled(navigation == nil || markdownScroll == nil)
            Divider()
            Button("Previous Subject") { navigation?.moveSubject(-1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(navigation == nil)
            Button("Next Subject") { navigation?.moveSubject(1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(navigation == nil)
            Divider()
            Button(topicStar?.isStarred == true ? "Remove Bookmark" : "Bookmark Topic") { topicStar?.toggle() }
                .keyboardShortcut("s", modifiers: [])
                .disabled(navigation == nil || topicStar == nil)
            Divider()
            Button("Toggle Sidebar") { navigation?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(navigation == nil)
            Button("Refresh Topics") { navigation?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(navigation?.canRefresh != true)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { navigation?.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(navigation == nil)
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { navigation?.showShortcuts() }
                .keyboardShortcut("?", modifiers: [])
                .disabled(navigation == nil)
        }
    }
}
#endif
