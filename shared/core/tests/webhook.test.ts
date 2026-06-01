import { describe, expect, it } from "vitest";
import { parseConfig } from "../src/config";
import type { WebhookEvent } from "../src/types";
import { buildWebhookRequest } from "../src/webhook";

const TS = 1_704_135_600_000;

function configWith(overrides: Record<string, unknown>) {
  return parseConfig({
    accountabilityWebhook: { isEnabled: true, endpointURLString: "https://hook.example", ...overrides },
  });
}

function event(over: Partial<WebhookEvent>): WebhookEvent {
  return {
    kind: "dismissed",
    timestampMs: TS,
    dateKey: "2024-01-01",
    windowID: "w1",
    snoozeCount: 0,
    dismissalReason: null,
    appId: null,
    ...over,
  };
}

describe("webhook rendering parity", () => {
  it("renders the default template with the reason", () => {
    const req = buildWebhookRequest(event({ dismissalReason: "calling it a night" }), configWith({}));
    expect(req!.body.message).toBe("I dismissed Work Screen Time because: calling it a night");
    expect(req!.headers["Content-Type"]).toBe("application/json");
    expect(req!.url).toBe("https://hook.example");
  });

  it("uses <No Reason Given> when the reason is blank", () => {
    const req = buildWebhookRequest(event({ dismissalReason: "" }), configWith({}));
    expect(req!.body.message).toBe("I dismissed Work Screen Time because: <No Reason Given>");
  });

  it("appends Reason: when the template lacks {{reason}}", () => {
    const req = buildWebhookRequest(event({ dismissalReason: "later" }), configWith({ messageTemplate: "I {{event}} the app" }));
    expect(req!.body.message).toBe("I dismissed the app\nReason: later");
  });

  it("renders enabled body fields and auth headers", () => {
    const req = buildWebhookRequest(
      event({ dismissalReason: "x" }),
      configWith({
        bearerToken: "tok",
        apiKey: "key",
        headers: [{ isEnabled: true, name: "X-Trace", value: "1" }],
        bodyFields: [{ isEnabled: true, key: "groupId", value: "ad@g.us" }],
      }),
    );
    expect(req!.body.groupId).toBe("ad@g.us");
    expect(req!.headers["Authorization"]).toBe("Bearer tok");
    expect(req!.headers["x-api-key"]).toBe("key");
    expect(req!.headers["X-Trace"]).toBe("1");
  });

  it("returns null when the webhook is disabled", () => {
    expect(buildWebhookRequest(event({}), parseConfig({}))).toBeNull();
  });
});
