import XCTest
@testable import LumaCore

final class PhotoRatingTests: XCTestCase {
    func testRatingClampsAndZeroMeansUnrated() {
        XCTAssertEqual(PhotoRating(-2).value, 0)
        XCTAssertEqual(PhotoRating(30).value, 9)
        XCTAssertEqual(PhotoRating(0).title, "未评分")
    }
    func testExactAndMinimumFilters() {
        XCTAssertTrue(RatingFilter.exact(0).includes(0))
        XCTAssertFalse(RatingFilter.exact(0).includes(1))
        XCTAssertTrue(RatingFilter.atLeast(5).includes(8))
        XCTAssertFalse(RatingFilter.atLeast(5).includes(4))
        XCTAssertTrue(RatingFilter.all.includes(0))
    }
    func testStoredFiltersRoundTripAndRejectInvalidValues() {
        for filter in [RatingFilter.all, .exact(0), .exact(9), .atLeast(5)] {
            XCTAssertEqual(RatingFilter(stored: filter.stored), filter)
        }
        XCTAssertEqual(RatingFilter(stored: "exact:10"), .all)
        XCTAssertEqual(RatingFilter(stored: "invalid"), .all)
    }
}
