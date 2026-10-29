import Foundation

/// Offsets outlive the bounded set of mounted subject lists, without retaining their views.
@MainActor
final class FeedScrollMemory {
    var offsets: [String: CGFloat] = [:]
}
