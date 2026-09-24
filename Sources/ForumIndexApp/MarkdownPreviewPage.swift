import ForumIndexCore
import Foundation

struct MarkdownPreviewPage: Identifiable {
    let id = UUID()
    let url: URL
    var reader: MarkdownTopicReader?
    var error: String?
}
