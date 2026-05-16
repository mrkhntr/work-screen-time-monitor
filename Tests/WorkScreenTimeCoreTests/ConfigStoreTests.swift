import XCTest
@testable import WorkScreenTimeCore

final class ConfigStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ConfigStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkScreenTimeAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ConfigStore(url: directory.appendingPathComponent("config.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingConfigFallsBackToDefaultAndCreatesFile() throws {
        try? FileManager.default.removeItem(at: store.url)

        XCTAssertEqual(store.load(), AppConfig.default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testCorruptConfigFallsBackToDefaultAndRewritesValidJSON() throws {
        try Data("nope".utf8).write(to: store.url)

        XCTAssertEqual(store.load(), AppConfig.default)

        let data = try Data(contentsOf: store.url)
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: data))
    }

    func testSaveNormalizesNumericBoundsAndEmptyQuotes() throws {
        var config = AppConfig.default
        config.warningLeadMinutes = -10
        config.snoozeMinutes = 0
        config.idleThresholdMinutes = -1
        config.quotes = []

        try store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.warningLeadMinutes, 0)
        XCTAssertEqual(loaded.snoozeMinutes, 1)
        XCTAssertEqual(loaded.idleThresholdMinutes, 1)
        XCTAssertEqual(loaded.quotes, AppConfig.defaultQuotes)
    }

    func testSaveNormalizesAccountabilityWebhook() throws {
        var config = AppConfig.default
        config.accountabilityWebhook = AccountabilityWebhookConfig(
            isEnabled: true,
            endpointURLString: "  https://example.com/hook  ",
            bearerToken: "  token  ",
            apiKey: "  api-key  ",
            messageTemplate: "   "
        )

        try store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.accountabilityWebhook?.isEnabled, true)
        XCTAssertEqual(loaded.accountabilityWebhook?.endpointURLString, "https://example.com/hook")
        XCTAssertEqual(loaded.accountabilityWebhook?.bearerToken, "token")
        XCTAssertEqual(loaded.accountabilityWebhook?.apiKey, "api-key")
        XCTAssertEqual(loaded.accountabilityWebhook?.messageTemplate, AccountabilityWebhookConfig().messageTemplate)
    }

    func testSaveDisablesAccountabilityWebhookWithoutURL() throws {
        var config = AppConfig.default
        config.accountabilityWebhook = AccountabilityWebhookConfig(isEnabled: true, endpointURLString: " ")

        try store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.accountabilityWebhook?.isEnabled, false)
    }

    func testLoadNormalizesMissingScheduleRowsFromJSON() throws {
        let monday = DaySchedule(
            weekday: .monday,
            isEnabled: false,
            start: TimeOfDay(hour: 7, minute: 30),
            end: TimeOfDay(hour: 8, minute: 45)
        )
        let partialConfig = AppConfig(
            schedules: [monday],
            warningLeadMinutes: -5,
            snoozeMinutes: 0,
            idleThresholdMinutes: 0,
            quotes: []
        )
        let data = try JSONEncoder().encode(partialConfig)
        try data.write(to: store.url)

        let loaded = store.load()

        XCTAssertEqual(loaded.schedules.count, Weekday.allCases.count)
        XCTAssertEqual(loaded.schedule(for: .monday), monday)
        XCTAssertEqual(loaded.schedule(for: .tuesday), AppConfig.default.schedule(for: .tuesday))
        XCTAssertEqual(loaded.schedule(for: .sunday), AppConfig.default.schedule(for: .sunday))
        XCTAssertEqual(loaded.warningLeadMinutes, 0)
        XCTAssertEqual(loaded.snoozeMinutes, 1)
        XCTAssertEqual(loaded.idleThresholdMinutes, 1)
        XCTAssertEqual(loaded.quotes, AppConfig.defaultQuotes)
    }

    func testSaveNormalizesScheduleOrderToWeekdayOrder() throws {
        let sunday = DaySchedule(
            weekday: .sunday,
            isEnabled: false,
            start: TimeOfDay(hour: 20, minute: 0),
            end: TimeOfDay(hour: 21, minute: 0)
        )
        let monday = DaySchedule(
            weekday: .monday,
            isEnabled: false,
            start: TimeOfDay(hour: 7, minute: 30),
            end: TimeOfDay(hour: 8, minute: 45)
        )
        let config = AppConfig(
            schedules: [monday, sunday],
            quotes: ["A real quote."]
        )

        try store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.schedules.map(\.weekday), Weekday.allCases)
        XCTAssertEqual(loaded.schedule(for: .sunday), sunday)
        XCTAssertEqual(loaded.schedule(for: .monday), monday)
        XCTAssertEqual(loaded.schedule(for: .tuesday), AppConfig.default.schedule(for: .tuesday))
    }
}
