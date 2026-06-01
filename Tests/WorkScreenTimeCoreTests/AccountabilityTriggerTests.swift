import XCTest
@testable import WorkScreenTimeCore

final class AccountabilityTriggerTests: XCTestCase {
    func testDoesNotNotifyBelowThreshold() {
        XCTAssertFalse(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 1, threshold: 3))
        XCTAssertFalse(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 2, threshold: 3))
    }

    func testNotifiesAtAndAboveThreshold() {
        XCTAssertTrue(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 3, threshold: 3))
        XCTAssertTrue(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 4, threshold: 3))
    }

    func testCustomThreshold() {
        XCTAssertTrue(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 1, threshold: 1))
        XCTAssertTrue(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 2, threshold: 2))
        XCTAssertFalse(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 1, threshold: 2))
    }

    func testZeroOrNegativeThresholdClampsToOne() {
        XCTAssertTrue(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 1, threshold: 0))
        XCTAssertTrue(AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: 1, threshold: -5))
    }

    func testDefaultThreshold() {
        XCTAssertEqual(AccountabilityTrigger.defaultSnoozeNotifyThreshold, 3)
    }
}
