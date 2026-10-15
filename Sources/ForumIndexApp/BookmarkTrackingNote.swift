import SwiftUI

struct BookmarkTrackingNote: View {
    var body: some View {
        Text("Your 20 most recently bookmarked topics are tracked for new replies.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
            .accessibilityIdentifier("bookmark-tracking-note")
    }
}
