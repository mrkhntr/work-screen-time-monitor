// Persisted enforcement state + history (Zod-validated so corrupt on-disk state
// degrades gracefully), plus the event/now input shapes. Mirrors AppModel's
// AppState and HistoryStore (Stores.swift / Models.swift).

import { z } from "zod";
import type { Effect } from "./types";

const HistoryEventSchema = z.object({
  timestampMs: z.number().catch(0),
  type: z.enum(["promptShown", "snoozed", "dismissed", "paused", "resumed"]).catch("promptShown"),
  windowID: z.string().nullable().catch(null),
  note: z.string().nullable().catch(null),
});

const DailySummaryInner = z.object({
  dateKey: z.string().catch(""),
  promptsShown: z.number().catch(0),
  snoozes: z.number().catch(0),
  dismissals: z.number().catch(0),
  lastDismissedWindowID: z.string().nullable().catch(null),
  lastDismissedAtMs: z.number().nullable().catch(null),
  dismissalReasons: z.array(z.string()).catch([]),
  events: z.array(HistoryEventSchema).catch([]),
});
export const DailySummarySchema = DailySummaryInner.catch(() => DailySummaryInner.parse({}));

const HistoryInner = z.object({
  dailySummaries: z.record(z.string(), DailySummarySchema).catch({}),
});
export const HistorySchema = HistoryInner.catch(() => HistoryInner.parse({}));

const CoreStateInner = z.object({
  mode: z.enum(["idle", "downtimeNormal", "snoozed", "paused", "prompting"]).catch("idle"),
  untilMs: z.number().nullable().catch(null),
  promptShownAtMs: z.number().nullable().catch(null),
  promptWindowId: z.string().nullable().catch(null),
  promptDateKey: z.string().nullable().catch(null),
  history: HistorySchema,
});
export const CoreStateSchema = CoreStateInner.catch(() => CoreStateInner.parse({}));

export type HistoryEvent = z.infer<typeof HistoryEventSchema>;
export type DailySummary = z.infer<typeof DailySummarySchema>;
export type History = z.infer<typeof HistorySchema>;
export type CoreState = z.infer<typeof CoreStateSchema>;

export function defaultState(): CoreState {
  return CoreStateSchema.parse({});
}
export function parseState(input: unknown): CoreState {
  return CoreStateSchema.parse(input);
}

export function emptySummary(dateKey: string): DailySummary {
  return { ...DailySummarySchema.parse({}), dateKey };
}

export const NowSchema = z.object({
  epochMs: z.number(),
  tzOffsetMin: z.number().catch(0),
});

export type CoreEvent =
  | { type: "tick"; idleSeconds?: number }
  | { type: "foregroundChanged"; appId: string; idleSeconds?: number }
  | { type: "userSnoozed"; reason?: string | null }
  | { type: "userDismissed"; reason?: string | null }
  | { type: "pauseRequested"; kind: "hour" | "tomorrow" }
  | { type: "resumeNow" }
  | { type: "enforceNow" }
  | { type: "permissionRevoked" };

export interface ReduceResult {
  state: CoreState;
  effects: Effect[];
}
