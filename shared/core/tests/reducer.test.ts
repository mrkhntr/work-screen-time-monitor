import { describe, expect, it } from "vitest";
import { parseConfig } from "../src/config";
import { reduce } from "../src/reducer";
import { defaultState } from "../src/state";
import type { Effect } from "../src/types";

const MON_MIDNIGHT_UTC = 1_704_067_200_000;
const H = 3_600_000;
const MON_19 = { epochMs: MON_MIDNIGHT_UTC + 19 * H, tzOffsetMin: 0 }; // inside Monday downtime

function mondayDowntime(extra: Record<string, unknown> = {}) {
  return parseConfig({
    schedules: [1, 2, 3, 4, 5, 6, 7].map((w) => ({
      weekday: w,
      isEnabled: w === 2,
      start: { hour: 18, minute: 0 },
      end: { hour: 6, minute: 0 },
    })),
    ...extra,
  });
}

const has = (effects: Effect[], type: Effect["type"]) => effects.some((e) => e.type === type);

describe("reducer state machine", () => {
  it("shows the overlay when active during downtime, then snoozes", () => {
    const config = mondayDowntime();
    const r1 = reduce(defaultState(), { type: "tick", idleSeconds: 0 }, MON_19, config);
    expect(r1.state.mode).toBe("prompting");
    expect(has(r1.effects, "showOverlay")).toBe(true);

    const r2 = reduce(r1.state, { type: "userSnoozed", reason: null }, MON_19, config);
    expect(r2.state.mode).toBe("snoozed");
    expect(has(r2.effects, "notifySnoozed")).toBe(true);
    expect(has(r2.effects, "sendWebhook")).toBe(false); // no webhook configured
    expect(r2.state.history.dailySummaries["2024-01-01"]!.snoozes).toBe(1);
  });

  it("does not prompt on tick when idle (no activity reported)", () => {
    const r = reduce(defaultState(), { type: "tick" }, MON_19, mondayDowntime());
    expect(r.state.mode).toBe("downtimeNormal");
    expect(has(r.effects, "showOverlay")).toBe(false);
  });

  it("dismiss always fires the webhook when enabled", () => {
    const config = mondayDowntime({ accountabilityWebhook: { isEnabled: true, endpointURLString: "https://h.example" } });
    const r1 = reduce(defaultState(), { type: "tick", idleSeconds: 0 }, MON_19, config);
    const r2 = reduce(r1.state, { type: "userDismissed", reason: "done" }, MON_19, config);
    expect(r2.state.mode).toBe("idle");
    expect(has(r2.effects, "sendWebhook")).toBe(true);
  });

  it("blocks a listed app via foregroundChanged during downtime", () => {
    const config = mondayDowntime({
      accountabilityWebhook: { isEnabled: true, endpointURLString: "https://h.example" },
      appBlocking: { isEnabled: true, blockedApps: [{ identifier: "com.slack", displayName: "Slack" }] },
    });
    const blocked = reduce(defaultState(), { type: "foregroundChanged", appId: "com.slack" }, MON_19, config);
    expect(blocked.state.mode).toBe("prompting");
    expect(has(blocked.effects, "showOverlay")).toBe(true);
    expect(has(blocked.effects, "sendWebhook")).toBe(true); // blockedAppOpened

    const allowed = reduce(defaultState(), { type: "foregroundChanged", appId: "com.apple.Terminal" }, MON_19, config);
    expect(allowed.state.mode).not.toBe("prompting");
  });

  it("fires the snooze webhook only once the threshold is reached", () => {
    const config = mondayDowntime({ accountabilityWebhook: { isEnabled: true, endpointURLString: "https://h.example", snoozeNotifyThreshold: 3 } });
    const seeded = defaultState();
    seeded.history.dailySummaries["2024-01-01"] = {
      dateKey: "2024-01-01", promptsShown: 0, snoozes: 2, dismissals: 0,
      lastDismissedWindowID: null, lastDismissedAtMs: null, dismissalReasons: [], events: [],
    };
    const r1 = reduce(seeded, { type: "tick", idleSeconds: 0 }, MON_19, config); // prompt
    const r2 = reduce(r1.state, { type: "userSnoozed", reason: null }, MON_19, config); // 3rd snooze
    expect(r2.state.history.dailySummaries["2024-01-01"]!.snoozes).toBe(3);
    expect(has(r2.effects, "sendWebhook")).toBe(true);
  });

  it("always emits status + scheduleWake", () => {
    const r = reduce(defaultState(), { type: "tick" }, MON_19, mondayDowntime());
    expect(has(r.effects, "setStatus")).toBe(true);
    expect(has(r.effects, "scheduleWake")).toBe(true);
  });
});
