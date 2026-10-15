#if os(macOS)
import ForumIndexCore
import SwiftUI

struct MacReaderSidebar: View {
    let destinations: [ReaderDestination]
    let selectedID: String?
    let showingStarred: Bool
    let hasUnreadBookmarks: Bool
    let displayName: (ReaderDestination) -> String
    let select: (ReaderDestination) -> Void
    let editSubjects: () -> Void
    let showStarred: () -> Void
    let showSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForumIndexLogo()
                .accessibilityIdentifier("mac-sidebar-logo")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 40)
                .padding(.bottom, 4)
                .gesture(WindowDragGesture())

            HStack {
                Text("Subjects").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button("Edit Subjects", systemImage: "slider.horizontal.3", action: editSubjects)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Choose and reorder subjects")
            }
            .padding()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(destinations) { destination in
                            sidebarButton(displayName(destination), icon: "text.bubble",
                                          selected: selectedID == destination.id) { select(destination) }
                                .id(destination.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("mac-sidebar-subjects")
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }

            Divider()
            VStack(spacing: 3) {
                sidebarButton("Bookmarks", icon: "bookmark", selected: showingStarred, action: showStarred)
                    .accessibilityIdentifier("mac-sidebar-starred")
                    .accessibilityValue(hasUnreadBookmarks ? "New replies" : "No new replies")
                sidebarButton("Settings", icon: "gearshape", selected: false, action: showSettings)
                    .accessibilityIdentifier("mac-sidebar-settings")
            }
            .padding(10)
        }
    }

    private func sidebarButton(_ title: String, icon: String, selected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: {
                if icon == "bookmark" { BookmarkIcon(hasUnreadReplies: hasUnreadBookmarks) }
                else { Image(systemName: icon) }
            }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
    }
}
#endif
