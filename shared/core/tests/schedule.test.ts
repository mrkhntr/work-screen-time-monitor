import { describe, expect, it } from "vitest";
import { defaultConfig, parseConfig } from "../src/config";
import { activeWindow, downtimeWindowForDay, nextDowntimeWindow } from "../src/schedule";
import type { Now } from "../src/types";

const MON_MIDNIGHT_UTC = 1_704_067_200_000; // 2024-01-01T00:00:00Z (a Monday)
const H = 3_600_000;
const utc = (epochMs: number): Now => ({ epochMs, tzOffsetMin: 0 });

// Only Monday enabled, 18:00 -> 06:00 (overnight) — all other days off.
function mondayOnly() {
  return parseConfig({
    schedules: [1, 2, 3, 4, 5, 6, 7].map((w) => ({
      weekday: w,
      isEnabled: w === 2,
      start: { hour: 18, minute: 0 },
      end: { hour: 6, minute: 0 },
    })),
  });
}

describe("ScheduleEngine parity", () => {
  it("is active inside an overnight window and exposes start/end as epoch ms", () => {
    const config = mondayOnly();
    const w = activeWindow(utc(MON_MIDNIGHT_UTC + 19 * H), config);
    expect(w).not.toBeNull();
    expect(w!.weekday).toBe(2);
    expect(w!.startMs).toBe(MON_MIDNIGHT_UTC + 18 * H); // Mon 18:00
    expect(w!.endMs).toBe(MON_MIDNIGHT_UTC + 24 * H + 6 * H); // Tue 06:00
    expect(w!.id).toBe("2024-01-01-monday-18:00-06:00");
  });

  it("morning side of an overnight window is owned by the start day", () => {
    const config = mondayOnly();
    const w = activeWindow(utc(MON_MIDNIGHT_UTC + 24 * H + 3 * H), config); // Tue 03:00
    expect(w).not.toBeNull();
    expect(w!.weekday).toBe(2); // Monday window
  });

  it("is inactive before the window starts", () => {
    expect(activeWindow(utc(MON_MIDNIGHT_UTC + 12 * H), mondayOnly())).toBeNull();
  });

  it("treats equal start/end as a 24h window", () => {
    const config = parseConfig({
      schedules: [1, 2, 3, 4, 5, 6, 7].map((w) => ({
        weekday: w,
        isEnabled: w === 2,
        start: { hour: 9, minute: 0 },
        end: { hour: 9, minute: 0 },
      })),
    });
    const w = activeWindow(utc(MON_MIDNIGHT_UTC + 12 * H), config); // Mon 12:00
    expect(w).not.toBeNull();
    expect(w!.startMs).toBe(MON_MIDNIGHT_UTC + 9 * H);
    expect(w!.endMs).toBe(MON_MIDNIGHT_UTC + 24 * H + 9 * H); // Tue 09:00
  });

  it("nextDowntimeWindow returns the upcoming window when outside downtime", () => {
    const w = nextDowntimeWindow(utc(MON_MIDNIGHT_UTC + 12 * H), mondayOnly());
    expect(w!.startMs).toBe(MON_MIDNIGHT_UTC + 18 * H);
  });

  it("downtimeWindowForDay handles a same-day window", () => {
    const config = defaultConfig();
    const sat = config.schedules.find((s) => s.weekday === 7)!; // 16:00 -> 10:00 overnight too
    expect(sat.start.hour).toBe(16);
  });
});
