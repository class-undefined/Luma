import XCTest
@testable import LumaCore

final class ThumbnailInteractionTests: XCTestCase {
    func testSizeBoundsAndDesignColumnCounts() {
        XCTAssertEqual(ThumbnailSize.medium.width, 272)
        XCTAssertEqual(ThumbnailSize.tiny.stepping(-1), .tiny)
        XCTAssertEqual(ThumbnailSize.huge.stepping(1), .huge)
        XCTAssertEqual(ThumbnailSize.allCases.map { GalleryGeometry(viewportWidth: 1224, size: $0).columns }, [8, 5, 4, 3, 2])
    }

    func testTrackpadRequiresAccumulationAndDoesNotQueueSteps() {
        var scroll = ScrollStepAccumulator()
        XCTAssertEqual(scroll.handle(delta: 12, precise: true, control: true, momentum: false, timestamp: 1).step, 0)
        XCTAssertEqual(scroll.handle(delta: 17, precise: true, control: true, momentum: false, timestamp: 1.02).step, 1)
        XCTAssertEqual(scroll.handle(delta: 200, precise: true, control: true, momentum: false, timestamp: 1.03).step, 0)
        XCTAssertEqual(scroll.handle(delta: 1, precise: true, control: true, momentum: false, timestamp: 1.2).step, 0)
        XCTAssertEqual(scroll.handle(delta: -29, precise: true, control: true, momentum: false, timestamp: 1.4).step, -1)
    }

    func testWheelAndOrdinaryScrollingAndMomentumTail() {
        var scroll = ScrollStepAccumulator()
        XCTAssertEqual(scroll.handle(delta: 1, precise: false, control: true, momentum: false, timestamp: 1).step, 1)
        let momentum = scroll.handle(delta: -60, precise: true, control: false, momentum: true, timestamp: 1.1)
        XCTAssertTrue(momentum.consumed)
        XCTAssertEqual(momentum.step, 0)
        XCTAssertFalse(scroll.handle(delta: -20, precise: true, control: false, momentum: false, began: true, timestamp: 2).consumed)
        XCTAssertFalse(scroll.handle(delta: -20, precise: true, control: false, momentum: true, timestamp: 2.1).consumed)
    }

    func testDirectionChangesResetAccumulation() {
        var scroll = ScrollStepAccumulator()
        _ = scroll.handle(delta: 20, precise: true, control: true, momentum: false, timestamp: 1)
        XCTAssertEqual(scroll.handle(delta: -20, precise: true, control: true, momentum: false, timestamp: 1.01).step, 0)
        XCTAssertEqual(scroll.handle(delta: -8, precise: true, control: true, momentum: false, timestamp: 1.02).step, -1)
    }

    func testReleasingControlBeforeGestureEndStillSuppressesMomentum() {
        var scroll = ScrollStepAccumulator()
        _ = scroll.handle(delta: 30, precise: true, control: true, momentum: false, began: true, timestamp: 1)
        _ = scroll.handle(delta: 0, precise: true, control: false, momentum: false, timestamp: 1.1)
        XCTAssertTrue(scroll.handle(delta: 20, precise: true, control: false, momentum: true, timestamp: 1.15).consumed)
        XCTAssertFalse(scroll.handle(delta: 20, precise: true, control: false, momentum: false, began: true, timestamp: 1.2).consumed)
    }
}
