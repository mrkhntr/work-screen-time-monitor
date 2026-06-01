import { describe, expect, it } from "vitest";
import { matchesConfirmationPhrase, normalizePhrase } from "../src/phrase";

describe("ConfirmationPhraseMatcher parity", () => {
  it("ignores case, spaces, and punctuation", () => {
    expect(matchesConfirmationPhrase("I am done for today", "i  am-done, for TODAY!")).toBe(true);
  });
  it("rejects different letters", () => {
    expect(matchesConfirmationPhrase("I am done", "I am don")).toBe(false);
  });
  it("normalizes to a-z only", () => {
    expect(normalizePhrase("  Ab3 c! ")).toBe("abc");
  });
});
