// Plain output/value types produced by the core. Config + persisted state +
// events are defined as Zod schemas in config.ts / state.ts (validated input);
// these are the trusted things the core *returns*.

export type Weekday = 1 | 2 | 3 | 4 | 5 | 6 | 7; // Sunday=1 ... Saturday=7 (Swift rawValue)

export type Mode = "idle" | "downtimeNormal" | "snoozed" | "paused" | "prompting";

/** Time, fully resolved by the native shell so the core never touches timezones.
 *  `tzOffsetMin` = minutes to ADD to UTC to get local time (Swift secondsFromGMT/60;
 *  Android ZoneOffset totalSeconds/60). e.g. New York EDT = -240. */
export interface Now {
  epochMs: number;
  tzOffsetMin: number;
}

export interface DowntimeWindow {
  id: string;
  weekday: Weekday;
  startMs: number; // epoch milliseconds
  endMs: number;
}

export interface EscalationState {
  snoozeCount: number;
  title: string;
  message: string;
  confirmationPhrase: string;
  requiresHold: boolean;
  requiresPhrase: boolean;
  requiresReason: boolean;
}

export type WebhookEventKind = "dismissed" | "snoozed" | "blockedAppOpened" | "permissionRevoked" | "test";

export interface WebhookEvent {
  kind: WebhookEventKind;
  timestampMs: number;
  dateKey: string;
  windowID: string | null;
  snoozeCount: number | null;
  dismissalReason: string | null;
  appId?: string | null;
}

export interface WebhookRequest {
  url: string;
  method: "POST";
  headers: Record<string, string>;
  body: Record<string, string>;
}

export type Effect =
  | { type: "showOverlay"; escalation: EscalationState; window: DowntimeWindow; dateKey: string; blockedAppId: string | null }
  | { type: "hideOverlay" }
  | { type: "notifySnoozed"; untilMs: number }
  | { type: "sendWebhook"; request: WebhookRequest }
  | { type: "scheduleWake"; atEpochMs: number }
  | {
      type: "setStatus";
      text: string;
      icon: string;
      snoozeCount: number;
      showsPauseActions: boolean;
      showsResumeAction: boolean;
      untilMs: number | null;
    };
