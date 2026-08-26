import Foundation

public enum ForumIndexCore {
    public static let appName = "Forum Index"

    public static func normalizedForumName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
