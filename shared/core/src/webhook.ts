// Mirrors AccountabilityWebhookNotifier.swift rendering: {{placeholder}}
// substitution (unknown placeholders preserved), <No Reason Given> fallback,
// and the "\nReason: …" append when the template lacks {{reason}}.

import type { AccountabilityWebhookConfig, AppConfig } from "./config";
import type { WebhookEvent, WebhookRequest } from "./types";

const MISSING_REASON = "<No Reason Given>";
const PLACEHOLDER = /\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g;
const trim = (s: string) => s.replace(/^\s+|\s+$/g, "");

function templateValues(event: WebhookEvent, message: string): Record<string, string> {
  const reasonTrim = trim(event.dismissalReason ?? "");
  const displayReason = reasonTrim.length ? reasonTrim : MISSING_REASON;
  return {
    app: "WorkScreenTimeApp",
    appId: event.appId ?? "",
    event: event.kind,
    message,
    timestamp: new Date(event.timestampMs).toISOString(),
    dateKey: event.dateKey,
    windowID: event.windowID ?? "",
    snoozeCount: event.snoozeCount == null ? "" : String(event.snoozeCount),
    reason: displayReason,
    dismissalReason: displayReason,
  };
}

function renderTemplate(template: string, values: Record<string, string>): string {
  return template.replace(PLACEHOLDER, (full, key: string) => (key in values ? values[key]! : full));
}

function renderedMessage(template: string, event: WebhookEvent): string {
  const reasonRaw = event.dismissalReason ?? "";
  let rendered = renderTemplate(template, templateValues(event, reasonRaw));
  const appendsReason = event.kind === "dismissed" || event.kind === "snoozed";
  if (appendsReason && reasonRaw.length > 0 && !template.includes("{{reason}}")) {
    rendered += `\nReason: ${reasonRaw}`;
  }
  return rendered;
}

/** Build the HTTP request for an enabled webhook, or null if it should not fire. */
export function buildWebhookRequest(event: WebhookEvent, config: AppConfig): WebhookRequest | null {
  const w = config.accountabilityWebhook;
  if (!w || !w.isEnabled || w.endpointURLString.length === 0) return null;
  return renderWebhookRequest(event, w);
}

/** Render the request for a given (assumed valid) webhook config — used by the test-send too. */
export function renderWebhookRequest(event: WebhookEvent, w: AccountabilityWebhookConfig): WebhookRequest {
  const message = renderedMessage(w.messageTemplate, event);
  const values = templateValues(event, message);

  const body: Record<string, string> = { message };
  for (const f of w.bodyFields) {
    if (f.isEnabled && f.key.length > 0) body[f.key] = renderTemplate(f.value, values);
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (w.bearerToken.length > 0) headers["Authorization"] = `Bearer ${w.bearerToken}`;
  if (w.apiKey.length > 0) headers["x-api-key"] = w.apiKey;
  for (const h of w.headers) {
    if (h.isEnabled && h.name.length > 0) headers[h.name] = h.value;
  }

  return { url: w.endpointURLString, method: "POST", headers, body };
}
