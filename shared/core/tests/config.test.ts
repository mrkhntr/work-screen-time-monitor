import { describe, expect, it } from "vitest";
import { DEFAULT_QUOTES, DEFAULT_SNOOZE_NOTIFY_THRESHOLD, defaultConfig, parseConfig } from "../src/config";

describe("config defaults + normalization (Zod)", () => {
  it("defaultConfig has all seven weekday rows and base values", () => {
    const c = defaultConfig();
    expect(c.schedules.map((s) => s.weekday)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(c.snoozeMinutes).toBe(15);
    expect(c.warningLeadMinutes).toBe(15);
    expect(c.accountabilityWebhook).toBeNull();
    expect(c.appBlocking).toBeNull();
  });

  it("parse({}) equals defaultConfig()", () => {
    expect(parseConfig({})).toEqual(defaultConfig());
  });

  it("clamps numeric bounds and restores empty quotes", () => {
    const c = parseConfig({ snoozeMinutes: 0, warningLeadMinutes: -10, idleThresholdMinutes: -1, quotes: ["  ", ""] });
    expect(c.snoozeMinutes).toBe(1);
    expect(c.warningLeadMinutes).toBe(0);
    expect(c.idleThresholdMinutes).toBe(1);
    expect(c.quotes).toEqual(DEFAULT_QUOTES);
  });

  it("fills missing weekday rows from defaults", () => {
    const c = parseConfig({ schedules: [{ weekday: 2, isEnabled: false, start: { hour: 7, minute: 30 }, end: { hour: 8, minute: 45 } }] });
    expect(c.schedules).toHaveLength(7);
    expect(c.schedules.find((s) => s.weekday === 2)!.isEnabled).toBe(false);
    expect(c.schedules.find((s) => s.weekday === 3)!.isEnabled).toBe(true); // default
  });

  it("disables the webhook when the URL is blank and defaults the threshold", () => {
    const c = parseConfig({ accountabilityWebhook: { isEnabled: true, endpointURLString: "  " } });
    expect(c.accountabilityWebhook!.isEnabled).toBe(false);
    expect(c.accountabilityWebhook!.snoozeNotifyThreshold).toBe(DEFAULT_SNOOZE_NOTIFY_THRESHOLD);
  });

  it("keeps a configured snooze threshold and trims app-blocking identifiers", () => {
    const c = parseConfig({
      accountabilityWebhook: { isEnabled: true, endpointURLString: "https://x.example", snoozeNotifyThreshold: 2 },
      appBlocking: { isEnabled: true, blockedApps: [{ identifier: "  com.foo  ", displayName: "Foo" }, { identifier: "" }] },
    });
    expect(c.accountabilityWebhook!.snoozeNotifyThreshold).toBe(2);
    expect(c.appBlocking!.blockedApps).toEqual([{ identifier: "com.foo", displayName: "Foo", isEnabled: true }]);
  });
});
