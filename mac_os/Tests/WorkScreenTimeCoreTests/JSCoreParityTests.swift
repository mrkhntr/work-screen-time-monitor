import XCTest
@testable import WorkScreenTimeCore

/// Proves the shared `core.js` brain loads and runs inside JavaScriptCore (the
/// real macOS engine, not just V8) and agrees with the Swift implementation.
final class JSCoreParityTests: XCTestCase {
    private func makeHost() throws -> JSCoreHost {
        try XCTUnwrap(JSCoreHost(), "core.js should load into JavaScriptCore")
    }

    func testBundleLoadsAndExposesApi() throws {
        let host = try makeHost()
        XCTAssertFalse(host.defaultConfigJSON().isEmpty)
        XCTAssertFalse(host.defaultStateJSON().isEmpty)
    }

    func testDefaultConfigMatchesSwiftDefault() throws {
        let host = try makeHost()
        let json = host.defaultConfigJSON()
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.schedules.count, 7)
        XCTAssertEqual(decoded.snoozeMinutes, AppConfig.default.snoozeMinutes)
        XCTAssertEqual(decoded.warningLeadMinutes, AppConfig.default.warningLeadMinutes)
        XCTAssertEqual(decoded.idleThresholdMinutes, AppConfig.default.idleThresholdMinutes)
        XCTAssertEqual(decoded.quotes, AppConfig.defaultQuotes)
        XCTAssertEqual(decoded.escalation, AppConfig.default.escalation)
        XCTAssertEqual(decoded.schedule(for: .monday), AppConfig.default.schedule(for: .monday))
        XCTAssertEqual(decoded.schedule(for: .saturday), AppConfig.default.schedule(for: .saturday))
    }

    func testReduceWindowMatchesSwiftScheduleEngine() throws {
        let host = try makeHost()

        // Monday 2024-01-01 19:00 UTC — inside the default Monday 18:00→06:00 window.
        let epochMs = 1_704_135_600_000
        let now = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
        let config = AppConfig.default
        let configJSON = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)

        let resultJSON = host.reduce(
            state: host.defaultStateJSON(),
            event: #"{"type":"tick","idleSeconds":0}"#,
            now: #"{"epochMs":1704135600000,"tzOffsetMin":0}"#,
            config: configJSON
        )

        let result = try JSONSerialization.jsonObject(with: Data(resultJSON.utf8)) as? [String: Any]
        let effects = result?["effects"] as? [[String: Any]] ?? []
        let overlay = effects.first { ($0["type"] as? String) == "showOverlay" }
        let jsWindowId = (overlay?["window"] as? [String: Any])?["id"] as? String

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let swiftWindow = ScheduleEngine(calendar: calendar).activeWindow(at: now, config: config)

        XCTAssertEqual(result?["state"] as? [String: Any] != nil ? (result?["state"] as? [String: Any])?["mode"] as? String : nil, "prompting")
        XCTAssertNotNil(jsWindowId)
        XCTAssertEqual(jsWindowId, swiftWindow?.id, "JS and Swift schedule engines must produce the same window id")
    }
}
