import XCTest
@testable import MacZones

final class SnapGestureTests: XCTestCase {
    func testTapWhileZonesOnDismisses() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 0.1, didExpand: false, zonesWereOnBeforePress: true),
            .dismiss)
    }

    func testTapWhileZonesOffKeepsSingle() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 0.1, didExpand: false, zonesWereOnBeforePress: false),
            .singleFollow)
    }

    func testHoldWithSweepFreezesMulti() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 1.0, didExpand: true, zonesWereOnBeforePress: true),
            .freezeMulti)
    }

    func testHoldWithSweepFromOffFreezesMulti() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 1.0, didExpand: true, zonesWereOnBeforePress: false),
            .freezeMulti)
    }

    func testLongHoldNoSweepKeepsSingle() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 1.0, didExpand: false, zonesWereOnBeforePress: true),
            .singleFollow)
    }

    func testFastReleaseWithSweepFreezesMulti() {
        // A quick but real multi-sweep must not be misread as a dismiss tap.
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 0.1, didExpand: true, zonesWereOnBeforePress: true),
            .freezeMulti)
    }
}
