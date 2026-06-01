import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/config";
import { escalationState } from "../src/escalation";

describe("escalationState parity", () => {
  const config = defaultConfig();

  it("uses the quote for the initial prompt and escalates thresholds", () => {
    const e0 = escalationState(0, config, "Rest now.");
    expect(e0.title).toBe("Time to stop working");
    expect(e0.message).toBe("Rest now.");
    expect(e0.requiresHold).toBe(false);

    expect(escalationState(2, config, null).requiresHold).toBe(true);
    expect(escalationState(2, config, null).requiresPhrase).toBe(false);

    const e3 = escalationState(3, config, null);
    expect(e3.requiresHold).toBe(true);
    expect(e3.requiresPhrase).toBe(true);
    expect(e3.requiresReason).toBe(true);
  });

  it("falls back to the configured confirmation phrase when quote is blank", () => {
    expect(escalationState(0, config, "   ").confirmationPhrase).toBe(config.escalation.confirmationPhrase);
    expect(escalationState(0, config, "Stop").confirmationPhrase).toBe("Stop");
  });
});
