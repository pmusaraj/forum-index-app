import SwiftUI

struct ForumIndexLogo: View {
    var body: some View {
        (
            Text("forum")
                .font(.custom("Avenir Next", size: 24, relativeTo: .title2).weight(.bold))
            + Text("i")
                .font(.custom("Avenir Next", size: 24, relativeTo: .title2).weight(.medium).italic())
                .foregroundColor(Color.accentColor)
            + Text("ndex")
                .font(.custom("Avenir Next", size: 24, relativeTo: .title2).weight(.medium))
                .foregroundColor(Color.accentColor)
        )
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityLabel("Forum Index")
    }
}
