import XCTest
@testable import ForumIndexCore

final class TopicTitleVisibilityTests: XCTestCase {
    func testRevealsOnUpwardScrollAndHidesOnDownwardScroll() {
        var state = TopicTitleVisibility()
        update(&state, 0)
        update(&state, 400)
        XCTAssertFalse(state.isVisible)
        update(&state, 395)
        XCTAssertFalse(state.isVisible)
        update(&state, 388)
        XCTAssertTrue(state.isVisible)
        update(&state, 388, scrolling: false)
        XCTAssertTrue(state.isVisible)
        update(&state, 393)
        XCTAssertTrue(state.isVisible)
        update(&state, 400)
        XCTAssertFalse(state.isVisible)
    }

    func testOriginalTitleAndTopBounceNeverShowDuplicate() {
        var state = TopicTitleVisibility()
        update(&state, 400)
        update(&state, 380)
        XCTAssertTrue(state.isVisible)
        update(&state, 80)
        XCTAssertFalse(state.isVisible)
        update(&state, -40)
        update(&state, 0)
        update(&state, 40)
        XCTAssertFalse(state.isVisible)
    }

    func testBottomBounceDoesNotRevealTitle() {
        var state = TopicTitleVisibility()
        update(&state, 1300)
        update(&state, 1400)
        update(&state, 1450)
        update(&state, 1420)
        update(&state, 1400)
        XCTAssertFalse(state.isVisible)
        update(&state, 1380)
        XCTAssertTrue(state.isVisible)
    }

    func testSmallDirectionChangesDoNotAccumulate() {
        var state = TopicTitleVisibility()
        update(&state, 400)
        for _ in 0..<10 {
            update(&state, 395)
            update(&state, 400)
        }
        XCTAssertFalse(state.isVisible)
    }

    func testLayoutChangesAndProgrammaticScrollingDoNotRevealTitle() {
        var state = TopicTitleVisibility()
        update(&state, 400)
        update(&state, 300, scrolling: false)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 200, titleBottom: 80, contentHeight: 3000, viewportHeight: 600, isScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 100, titleBottom: 90, contentHeight: 3000, viewportHeight: 700, isScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 200, titleBottom: 90, contentHeight: 3000, viewportHeight: 700, isScrolling: true)
        state.update(offset: 180, titleBottom: 90, contentHeight: 3000, viewportHeight: 700, isScrolling: true)
        XCTAssertTrue(state.isVisible)
    }

    private func update(_ state: inout TopicTitleVisibility, _ offset: Double, scrolling: Bool = true) {
        state.update(offset: offset, titleBottom: 80, contentHeight: 2000, viewportHeight: 600, isScrolling: scrolling)
    }
}
