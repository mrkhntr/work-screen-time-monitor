import { describe, expect, it } from "vitest";
import { notifiesOnSnooze } from "../src/accountability";

describe("AccountabilityTrigger parity", () => {
  it("does not notify below threshold", () => {
    expect(notifiesOnSnooze(1, 3)).toBe(false);
    expect(notifiesOnSnooze(2, 3)).toBe(false);
  });
  it("notifies at and above threshold", () => {
    expect(notifiesOnSnooze(3, 3)).toBe(true);
    expect(notifiesOnSnooze(4, 3)).toBe(true);
  });
  it("clamps a zero/negative threshold to 1", () => {
    expect(notifiesOnSnooze(1, 0)).toBe(true);
    expect(notifiesOnSnooze(1, -5)).toBe(true);
  });
});
