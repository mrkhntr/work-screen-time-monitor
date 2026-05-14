import XCTest
@testable import WorkScreenTimeCore

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkScreenTimeAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = HistoryStore(url: directory.appendingPathComponent("history.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRecordsDailyPromptSnoozeAndDismissal() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try store.recordPrompt(dateKey: "2027-01-15", windowID: "window", at: date)
        try store.recordSnooze(dateKey: "2027-01-15", windowID: "window", until: date.addingTimeInterval(900), at: date)
        try store.recordDismissal(dateKey: "2027-01-15", windowID: "window", reason: "I am closing up.", at: date)

        let summary = store.summary(for: "2027-01-15")
        XCTAssertEqual(summary.promptsShown, 1)
        XCTAssertEqual(summary.snoozes, 1)
        XCTAssertEqual(summary.dismissals, 1)
        XCTAssertEqual(summary.lastDismissedWindowID, "window")
        XCTAssertEqual(summary.dismissalReasons, ["I am closing up."])
        XCTAssertEqual(summary.events.map(\.type), [.promptShown, .snoozed, .dismissed])
    }

    func testRecordsPauseAndResumeEvents() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let pauseUntil = date.addingTimeInterval(3_600)

        try store.recordPause(dateKey: "2027-01-15", until: pauseUntil, at: date)
        try store.recordResume(dateKey: "2027-01-15", at: date.addingTimeInterval(60))

        let summary = store.summary(for: "2027-01-15")
        XCTAssertEqual(summary.events.map(\.type), [.paused, .resumed])
        XCTAssertNil(summary.events.first?.windowID)
        XCTAssertEqual(summary.events.first?.note, pauseUntil.ISO8601Format())
        XCTAssertNil(summary.events.last?.note)
    }

    func testClearDismissalReEnablesDismissedWindow() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        try store.recordDismissal(dateKey: "2027-01-15", windowID: "window", reason: "done", at: date)
        try store.clearDismissal(dateKey: "2027-01-15", windowID: "window", at: date.addingTimeInterval(60))

        let summary = store.summary(for: "2027-01-15")
        XCTAssertNil(summary.lastDismissedWindowID)
        XCTAssertNil(summary.lastDismissedAt)
        XCTAssertEqual(summary.dismissals, 1)
        XCTAssertEqual(summary.events.map(\.type), [.dismissed, .resumed])
        XCTAssertEqual(summary.events.last?.windowID, "window")
    }

    func testBlankDismissalReasonIsNotAddedToReasonList() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        try store.recordDismissal(dateKey: "2027-01-15", windowID: "window", reason: " \n ", at: date)

        let summary = store.summary(for: "2027-01-15")
        XCTAssertEqual(summary.dismissals, 1)
        XCTAssertEqual(summary.dismissalReasons, [])
        XCTAssertEqual(summary.events.count, 1)
        XCTAssertNil(summary.events.first?.note)
    }

    func testSummariesRemainSeparatedByDateKey() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        try store.recordPrompt(dateKey: "2027-01-15", windowID: "first", at: date)
        try store.recordSnooze(dateKey: "2027-01-16", windowID: "second", until: date.addingTimeInterval(900), at: date)

        let first = store.summary(for: "2027-01-15")
        let second = store.summary(for: "2027-01-16")

        XCTAssertEqual(first.promptsShown, 1)
        XCTAssertEqual(first.snoozes, 0)
        XCTAssertEqual(first.events.map(\.windowID), ["first"])
        XCTAssertEqual(second.promptsShown, 0)
        XCTAssertEqual(second.snoozes, 1)
        XCTAssertEqual(second.events.map(\.windowID), ["second"])
    }

    func testMissingJSONFallsBackToEmptyHistoryAndCreatesFile() throws {
        try? FileManager.default.removeItem(at: store.url)

        XCTAssertEqual(store.load(), History())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testCorruptJSONFallsBackToEmptyHistory() throws {
        try Data("nope".utf8).write(to: directory.appendingPathComponent("history.json"))

        XCTAssertEqual(store.load(), History())
    }

    func testClearRemovesStoredSummaries() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try store.recordPrompt(dateKey: "2027-01-15", windowID: "window", at: date)

        try store.clear()

        XCTAssertEqual(store.load(), History())
    }

    func testClearDateKeyRemovesOnlyThatSummary() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try store.recordPrompt(dateKey: "2027-01-15", windowID: "first", at: date)
        try store.recordPrompt(dateKey: "2027-01-16", windowID: "second", at: date)

        try store.clear(dateKey: "2027-01-15")

        XCTAssertEqual(store.summary(for: "2027-01-15"), DailySummary(dateKey: "2027-01-15"))
        XCTAssertEqual(store.summary(for: "2027-01-16").promptsShown, 1)
        XCTAssertEqual(store.summary(for: "2027-01-16").events.first?.windowID, "second")
    }
}
