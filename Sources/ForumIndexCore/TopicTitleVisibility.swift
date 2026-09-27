import Foundation

/// Tracks deliberate scroll direction without treating bounce or layout changes as scrolling.
public struct TopicTitleVisibility: Equatable, Sendable {
    public private(set) var isVisible = false
    private var previousOffset: Double?
    private var previousContentHeight: Double?
    private var previousViewportHeight: Double?
    private var previousTitleBottom: Double?
    private var travel: Double = 0

    public init() {}

    public mutating func update(
        offset: Double, titleBottom: Double, contentHeight: Double,
        viewportHeight: Double, isScrolling: Bool
    ) {
        let offset = min(max(0, offset), max(0, contentHeight - viewportHeight))
        defer {
            previousOffset = offset
            previousContentHeight = contentHeight
            previousViewportHeight = viewportHeight
            previousTitleBottom = titleBottom
        }
        guard titleBottom > 0, offset > titleBottom else {
            isVisible = false
            travel = 0
            return
        }
        guard isScrolling, let previousOffset,
              previousContentHeight == contentHeight,
              previousViewportHeight == viewportHeight,
              previousTitleBottom == titleBottom else {
            travel = 0
            return
        }
        let delta = offset - previousOffset
        guard delta != 0 else { return }
        if (delta > 0 && travel < 0) || (delta < 0 && travel > 0) { travel = 0 }
        travel += delta
        if travel <= -12 {
            isVisible = true
            travel = -12
        } else if travel >= 12 {
            isVisible = false
            travel = 12
        }
    }
}
