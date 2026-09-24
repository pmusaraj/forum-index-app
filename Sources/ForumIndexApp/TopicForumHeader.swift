import ForumIndexCore
import SwiftUI

struct TopicForumHeader: View {
    let forum: ForumSummary
    let isFullPageReady: Bool
    let usesWebView: Bool
    let toggleView: () -> Void
    var goBack: (() -> Void)? = nil
    var safeAreaInsets = EdgeInsets()
    @State private var showsOverview = false

    var body: some View {
        HStack(spacing: 10) {
            if let goBack {
                Button("Previous topic", systemImage: "chevron.left", action: goBack)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("topic-header-back")
            }
            Button { showsOverview = true } label: {
                HStack(spacing: 10) {
                    AsyncImage(url: forum.iconURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
                    Text(ForumPresentation.displayName(forum.name))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows site information")
            .accessibilityIdentifier("topic-header-forum-overview")
            .popover(isPresented: $showsOverview, arrowEdge: .top) {
                ForumOverview(forumID: forum.id)
                    .id(forum.id)
                    .presentationCompactAdaptation(.popover)
            }
            Spacer(minLength: 0)
            Button(usesWebView ? "Show Markdown preview" : "View full topic",
                   systemImage: usesWebView ? "doc.text" : "safari", action: toggleView)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("topic-header-full-html")
                .accessibilityValue(usesWebView ? "Full page" : (isFullPageReady ? "Ready" : "Loading full page"))
        }
        .padding(.leading, safeAreaInsets.leading + 20)
        .padding(.trailing, safeAreaInsets.trailing + 20)
        .padding(.top, safeAreaInsets.top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("BrandSurface"), ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) { Divider().overlay(Color("BrandSurface")) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("topic-forum-header")
    }
}
