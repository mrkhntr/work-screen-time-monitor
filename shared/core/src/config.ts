// Config schema, defaults, and normalization — defined once with Zod, the
// single source of truth for both apps. Mirrors AppConfig.default (Models.swift)
// and ConfigStore.normalized() (Stores.swift). Types are derived via z.infer.

import { z } from "zod";
import type { Weekday } from "./types";

export const DEFAULT_QUOTES: string[] = [
  "You have done enough for today. Future you deserves rest.",
  "Stopping is part of the work. Let the day close.",
  "Your life is bigger than this session.",
  "Rest is not a reward for finishing everything.",
  "One more task can wait. Your evening should not.",
];

export const DEFAULT_CONFIRMATION_PHRASE = "I am done for today";
export const DEFAULT_WEBHOOK_TEMPLATE = "I {{event}} Work Screen Time because: {{reason}}";
export const DEFAULT_SNOOZE_NOTIFY_THRESHOLD = 3;
export const WEEKDAYS: Weekday[] = [1, 2, 3, 4, 5, 6, 7];

const WEEKDAY_NAMES: Record<Weekday, string> = {
  1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday",
};
export function weekdayName(weekday: Weekday): string {
  return WEEKDAY_NAMES[weekday];
}

const trim = (s: string) => s.replace(/^\s+|\s+$/g, "");
const clampInt = (n: number, min: number, max = Number.MAX_SAFE_INTEGER) =>
  Math.min(Math.max(Math.trunc(n), min), max);

const WeekdaySchema = z.union([
  z.literal(1), z.literal(2), z.literal(3), z.literal(4), z.literal(5), z.literal(6), z.literal(7),
]);

const TimeOfDaySchema = z
  .object({ hour: z.number().catch(0), minute: z.number().catch(0) })
  .catch(() => ({ hour: 0, minute: 0 }))
  .transform((t) => ({ hour: clampInt(t.hour, 0, 23), minute: clampInt(t.minute, 0, 59) }));

const DayScheduleSchema = z.object({
  weekday: WeekdaySchema,
  isEnabled: z.boolean().catch(true),
  start: TimeOfDaySchema,
  end: TimeOfDaySchema,
});

const EscalationInner = z.object({
  holdRequiredAtSnoozeCount: z.number().catch(2).transform((n) => clampInt(n, 0)),
  phraseRequiredAtSnoozeCount: z.number().catch(3).transform((n) => clampInt(n, 0)),
  reasonRequiredAtSnoozeCount: z.number().catch(3).transform((n) => clampInt(n, 0)),
  confirmationPhrase: z
    .string()
    .catch(DEFAULT_CONFIRMATION_PHRASE)
    .transform((s) => (trim(s).length ? trim(s) : DEFAULT_CONFIRMATION_PHRASE)),
});
const EscalationConfigSchema = EscalationInner.catch(() => EscalationInner.parse({}));

const WebhookHeaderSchema = z.object({
  isEnabled: z.boolean().catch(true),
  name: z.string().catch(""),
  value: z.string().catch(""),
});
const WebhookBodyFieldSchema = z.object({
  isEnabled: z.boolean().catch(true),
  key: z.string().catch(""),
  value: z.string().catch(""),
});

const WebhookInner = z
  .object({
    isEnabled: z.boolean().catch(false),
    endpointURLString: z.string().catch(""),
    bearerToken: z.string().catch(""),
    apiKey: z.string().catch(""),
    headers: z.array(WebhookHeaderSchema).catch([]),
    messageTemplate: z.string().catch(DEFAULT_WEBHOOK_TEMPLATE),
    bodyFields: z.array(WebhookBodyFieldSchema).catch([]),
    snoozeNotifyThreshold: z.number().catch(DEFAULT_SNOOZE_NOTIFY_THRESHOLD).transform((n) => Math.trunc(n)),
  })
  .transform((w) => {
    const endpoint = trim(w.endpointURLString);
    const template = trim(w.messageTemplate);
    return {
      isEnabled: endpoint.length === 0 ? false : w.isEnabled,
      endpointURLString: endpoint,
      bearerToken: trim(w.bearerToken),
      apiKey: trim(w.apiKey),
      headers: w.headers
        .map((h) => ({ isEnabled: h.isEnabled, name: trim(h.name), value: trim(h.value) }))
        .filter((h) => !(h.name.length === 0 && h.value.length === 0)),
      messageTemplate: template.length === 0 ? DEFAULT_WEBHOOK_TEMPLATE : template,
      bodyFields: w.bodyFields
        .map((f) => ({ isEnabled: f.isEnabled, key: trim(f.key), value: trim(f.value) }))
        .filter((f) => !(f.key.length === 0 && f.value.length === 0)),
      snoozeNotifyThreshold: w.snoozeNotifyThreshold,
    };
  });
const WebhookConfigSchema = WebhookInner.catch(() => WebhookInner.parse({}));

const BlockedAppSchema = z.object({
  identifier: z.string().catch(""),
  displayName: z.string().catch(""),
  isEnabled: z.boolean().catch(true),
});
const AppBlockingInner = z
  .object({
    isEnabled: z.boolean().catch(false),
    blockAllApps: z.boolean().catch(false),
    blockedApps: z.array(BlockedAppSchema).catch([]),
  })
  .transform((b) => ({
    isEnabled: b.isEnabled,
    blockAllApps: b.blockAllApps,
    blockedApps: b.blockedApps
      .map((a) => ({ identifier: trim(a.identifier), displayName: trim(a.displayName), isEnabled: a.isEnabled }))
      .filter((a) => a.identifier.length > 0),
  }));
const AppBlockingConfigSchema = AppBlockingInner.catch(() => AppBlockingInner.parse({}));

export function defaultSchedule(weekday: Weekday): z.infer<typeof DayScheduleSchema> {
  const isWeekend = weekday === 1 || weekday === 7;
  return isWeekend
    ? { weekday, isEnabled: true, start: { hour: 16, minute: 0 }, end: { hour: 10, minute: 0 } }
    : { weekday, isEnabled: true, start: { hour: 18, minute: 0 }, end: { hour: 6, minute: 0 } };
}

function fillWeekdayRows(schedules: z.infer<typeof DayScheduleSchema>[]): z.infer<typeof DayScheduleSchema>[] {
  const existing = new Map<Weekday, z.infer<typeof DayScheduleSchema>>();
  for (const s of schedules) existing.set(s.weekday, s);
  return WEEKDAYS.map((w) => existing.get(w) ?? defaultSchedule(w));
}

const AppConfigInner = z
  .object({
    schedules: z.array(DayScheduleSchema).catch([]),
    warningLeadMinutes: z.number().catch(15).transform((n) => clampInt(n, 0)),
    snoozeMinutes: z.number().catch(15).transform((n) => clampInt(n, 1)),
    idleThresholdMinutes: z.number().catch(1).transform((n) => clampInt(n, 1)),
    quotes: z.array(z.string()).catch([]),
    escalation: EscalationConfigSchema,
    accountabilityWebhook: WebhookInner.nullable().catch(null).default(null),
    appBlocking: AppBlockingInner.nullable().catch(null).default(null),
  })
  .transform((c) => {
    const quotes = c.quotes.map(trim).filter((q) => q.length > 0);
    return {
      ...c,
      schedules: fillWeekdayRows(c.schedules),
      quotes: quotes.length ? quotes : [...DEFAULT_QUOTES],
    };
  });

export const AppConfigSchema = AppConfigInner.catch(() => AppConfigInner.parse({}));

export type TimeOfDay = z.infer<typeof TimeOfDaySchema>;
export type DaySchedule = z.infer<typeof DayScheduleSchema>;
export type EscalationConfig = z.infer<typeof EscalationConfigSchema>;
export type AccountabilityWebhookConfig = z.infer<typeof WebhookConfigSchema>;
export type BlockedApp = z.infer<typeof BlockedAppSchema>;
export type AppBlockingConfig = z.infer<typeof AppBlockingConfigSchema>;
export type AppConfig = z.infer<typeof AppConfigSchema>;

export function parseConfig(input: unknown): AppConfig {
  return AppConfigSchema.parse(input);
}
export function defaultConfig(): AppConfig {
  return AppConfigSchema.parse({});
}
export function scheduleFor(config: AppConfig, weekday: Weekday): DaySchedule | undefined {
  return config.schedules.find((s) => s.weekday === weekday);
}
export function timeMinutes(t: TimeOfDay): number {
  return clampInt(t.hour, 0, 23) * 60 + clampInt(t.minute, 0, 59);
}
export function timeStorage(t: TimeOfDay): string {
  const pad = (n: number) => String(clampInt(n, 0, 59)).padStart(2, "0");
  return `${String(clampInt(t.hour, 0, 23)).padStart(2, "0")}:${pad(t.minute)}`;
}
