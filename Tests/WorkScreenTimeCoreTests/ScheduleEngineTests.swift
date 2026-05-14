import XCTest
@testable import WorkScreenTimeCore

final class ScheduleEngineTests: XCTestCase {
    private var calendar: Calendar!
    private var engine: ScheduleEngine!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        engine = ScheduleEngine(calendar: calendar)
    }

    func testDefaultWeekdayOvernightWindowIsActiveAfterStart() {
        let date = makeDate(year: 2026, month: 5, day: 13, hour: 19, minute: 0)
        let window = engine.activeWindow(at: date, config: .default)

        XCTAssertEqual(window?.weekday, .wednesday)
        XCTAssertEqual(window?.start, makeDate(year: 2026, month: 5, day: 13, hour: 18, minute: 0))
        XCTAssertEqual(window?.end, makeDate(year: 2026, month: 5, day: 14, hour: 6, minute: 0))
    }

    func testDefaultWeekdayOvernightWindowIsActiveNextMorning() {
        let date = makeDate(year: 2026, month: 5, day: 14, hour: 5, minute: 30)
        let window = engine.activeWindow(at: date, config: .default)

        XCTAssertEqual(window?.weekday, .wednesday)
        XCTAssertEqual(window?.start, makeDate(year: 2026, month: 5, day: 13, hour: 18, minute: 0))
    }

    func testWindowEndsAtConfiguredEndTime() {
        let date = makeDate(year: 2026, month: 5, day: 14, hour: 6, minute: 0)
        let window = engine.activeWindow(at: date, config: .default)

        XCTAssertNil(window)
    }

    func testSameDayWindowIsInclusiveAtStartAndExclusiveAtEnd() {
        let config = configWithSchedules([
            DaySchedule(
                weekday: .wednesday,
                isEnabled: true,
                start: TimeOfDay(hour: 9, minute: 0),
                end: TimeOfDay(hour: 17, minute: 0)
            )
        ])

        XCTAssertNil(engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 13, hour: 8, minute: 59),
            config: config
        ))
        XCTAssertNotNil(engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 13, hour: 9, minute: 0),
            config: config
        ))
        XCTAssertNotNil(engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 13, hour: 16, minute: 59),
            config: config
        ))
        XCTAssertNil(engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 13, hour: 17, minute: 0),
            config: config
        ))
    }

    func testEqualStartAndEndCreatesTwentyFourHourWindow() {
        let config = configWithSchedules([
            DaySchedule(
                weekday: .wednesday,
                isEnabled: true,
                start: TimeOfDay(hour: 8, minute: 0),
                end: TimeOfDay(hour: 8, minute: 0)
            )
        ])

        let atStart = engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 13, hour: 8, minute: 0),
            config: config
        )
        let beforeEnd = engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 14, hour: 7, minute: 59),
            config: config
        )
        let atEnd = engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 14, hour: 8, minute: 0),
            config: config
        )

        XCTAssertEqual(atStart?.start, makeDate(year: 2026, month: 5, day: 13, hour: 8, minute: 0))
        XCTAssertEqual(atStart?.end, makeDate(year: 2026, month: 5, day: 14, hour: 8, minute: 0))
        XCTAssertEqual(beforeEnd?.weekday, .wednesday)
        XCTAssertNil(atEnd)
    }

    func testDisabledDayDoesNotCreateActiveWindow() {
        var config = AppConfig.default
        config.schedules = config.schedules.map {
            $0.weekday == .wednesday
                ? DaySchedule(weekday: $0.weekday, isEnabled: false, start: $0.start, end: $0.end)
                : $0
        }

        let date = makeDate(year: 2026, month: 5, day: 13, hour: 19, minute: 0)
        XCTAssertNil(engine.activeWindow(at: date, config: config))
    }

    func testDisabledStartDayDoesNotCarryOverIntoNextMorning() {
        var config = AppConfig.default
        config.schedules = config.schedules.map {
            $0.weekday == .wednesday
                ? DaySchedule(weekday: $0.weekday, isEnabled: false, start: $0.start, end: $0.end)
                : $0
        }

        let date = makeDate(year: 2026, month: 5, day: 14, hour: 5, minute: 30)
        XCTAssertNil(engine.activeWindow(at: date, config: config))
    }

    func testUpcomingWarningUsesLeadTime() {
        var config = AppConfig.default
        config.warningLeadMinutes = 15
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)

        let next = engine.upcomingWarningDates(from: now, config: config).first

        XCTAssertEqual(next?.window.weekday, .wednesday)
        XCTAssertEqual(next?.warningDate, makeDate(year: 2026, month: 5, day: 13, hour: 17, minute: 45))
    }

    func testUpcomingWarningSkipsElapsedWarningForCurrentDay() {
        var config = AppConfig.default
        config.warningLeadMinutes = 15
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 17, minute: 50)

        let next = engine.upcomingWarningDates(from: now, config: config).first

        XCTAssertEqual(next?.window.weekday, .thursday)
        XCTAssertEqual(next?.warningDate, makeDate(year: 2026, month: 5, day: 14, hour: 17, minute: 45))
    }

    func testUpcomingWarningClampsNegativeLeadTimeToWindowStart() {
        var config = AppConfig.default
        config.warningLeadMinutes = -30
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 17, minute: 59)

        let next = engine.upcomingWarningDates(from: now, config: config).first

        XCTAssertEqual(next?.window.weekday, .wednesday)
        XCTAssertEqual(next?.warningDate, makeDate(year: 2026, month: 5, day: 13, hour: 18, minute: 0))
    }

    func testEscalationThresholds() {
        let config = AppConfig.default

        XCTAssertFalse(engine.escalationState(snoozeCount: 1, config: config, quote: nil).requiresHold)
        XCTAssertTrue(engine.escalationState(snoozeCount: 2, config: config, quote: nil).requiresHold)
        XCTAssertTrue(engine.escalationState(snoozeCount: 3, config: config, quote: nil).requiresPhrase)
        XCTAssertTrue(engine.escalationState(snoozeCount: 3, config: config, quote: nil).requiresReason)
    }

    func testEscalationUsesCustomThresholdsInclusively() {
        let config = AppConfig(
            schedules: AppConfig.default.schedules,
            quotes: AppConfig.defaultQuotes,
            escalation: EscalationConfig(
                holdRequiredAtSnoozeCount: 5,
                phraseRequiredAtSnoozeCount: 6,
                reasonRequiredAtSnoozeCount: 7,
                confirmationPhrase: "done"
            )
        )

        let beforeHold = engine.escalationState(snoozeCount: 4, config: config, quote: nil)
        let atHold = engine.escalationState(snoozeCount: 5, config: config, quote: nil)
        let atPhrase = engine.escalationState(snoozeCount: 6, config: config, quote: nil)
        let atReason = engine.escalationState(snoozeCount: 7, config: config, quote: nil)

        XCTAssertFalse(beforeHold.requiresHold)
        XCTAssertTrue(atHold.requiresHold)
        XCTAssertFalse(atHold.requiresPhrase)
        XCTAssertTrue(atPhrase.requiresPhrase)
        XCTAssertFalse(atPhrase.requiresReason)
        XCTAssertTrue(atReason.requiresReason)
    }

    func testEscalationUsesProvidedQuoteOnlyForInitialPrompt() {
        let config = AppConfig.default

        XCTAssertEqual(
            engine.escalationState(snoozeCount: 0, config: config, quote: "Close it down.").message,
            "Close it down."
        )
        XCTAssertNotEqual(
            engine.escalationState(snoozeCount: 1, config: config, quote: "Close it down.").message,
            "Close it down."
        )
    }

    func testDuplicateScheduleRowsUseFirstMatchingSchedule() {
        let config = configWithSchedules([
            DaySchedule(
                weekday: .wednesday,
                isEnabled: true,
                start: TimeOfDay(hour: 9, minute: 0),
                end: TimeOfDay(hour: 10, minute: 0)
            ),
            DaySchedule(
                weekday: .wednesday,
                isEnabled: true,
                start: TimeOfDay(hour: 18, minute: 0),
                end: TimeOfDay(hour: 19, minute: 0)
            )
        ])

        XCTAssertNotNil(engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 13, hour: 9, minute: 30),
            config: config
        ))
        XCTAssertNil(engine.activeWindow(
            at: makeDate(year: 2026, month: 5, day: 13, hour: 18, minute: 30),
            config: config
        ))
    }

    func testTimeOfDayClampsOutOfRangeComponents() {
        XCTAssertEqual(TimeOfDay(hour: -1, minute: -5), TimeOfDay(hour: 0, minute: 0))
        XCTAssertEqual(TimeOfDay(hour: 24, minute: 60), TimeOfDay(hour: 23, minute: 59))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func configWithSchedules(_ schedules: [DaySchedule]) -> AppConfig {
        AppConfig(schedules: schedules, quotes: AppConfig.defaultQuotes)
    }
}
