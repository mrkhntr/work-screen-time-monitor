// The state machine — a pure port of AppModel's orchestration (AppModel.swift).
// reduce(state, event, now, config) -> { state, effects }. Native shells feed
// events with a resolved `now` and execute the returned effects.

import { notifiesOnSnooze } from "./accountability";
import type { AppConfig } from "./config";
import { escalationState } from "./escalation";
import { activeWindow, nextDowntimeWindow } from "./schedule";
import type { CoreEvent, CoreState, DailySummary, History, ReduceResult } from "./state";
import { emptySummary } from "./state";
import { dateKey as dateKeyForNow, dayIndexFromLocalMs, localMs, weekdayFromDayIndex } from "./time";
import type { DowntimeWindow, Effect, Now, WebhookEvent, WebhookEventKind } from "./types";
import { buildWebhookRequest } from "./webhook";

const HOUR_MS = 3_600_000;
const MIN_MS = 60_000;
const DAY_MS = 86_400_000;

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}
function dateKeyForMs(ms: number, tzOffsetMin: number): string {
  return dateKeyForNow({ epochMs: ms, tzOffsetMin });
}
function getOrCreateSummary(history: History, key: string): DailySummary {
  let s = history.dailySummaries[key];
  if (!s) {
    s = emptySummary(key);
    history.dailySummaries[key] = s;
  }
  return s;
}
function summaryFor(history: History, key: string): DailySummary {
  return history.dailySummaries[key] ?? emptySummary(key);
}
function trim(s: string): string {
  return s.replace(/^\s+|\s+$/g, "");
}

// ---- history mutations (mirror HistoryStore) ----
function recordPrompt(h: History, key: string, windowId: string, ts: number) {
  const s = getOrCreateSummary(h, key);
  s.promptsShown += 1;
  s.events.push({ timestampMs: ts, type: "promptShown", windowID: windowId, note: null });
}
function recordSnooze(h: History, key: string, windowId: string, untilMs: number, ts: number) {
  const s = getOrCreateSummary(h, key);
  s.snoozes += 1;
  s.events.push({ timestampMs: ts, type: "snoozed", windowID: windowId, note: new Date(untilMs).toISOString() });
}
function recordDismissal(h: History, key: string, windowId: string, reason: string | null, ts: number) {
  const s = getOrCreateSummary(h, key);
  const note = reason != null && trim(reason).length > 0 ? trim(reason) : null;
  s.dismissals += 1;
  s.lastDismissedWindowID = windowId;
  s.lastDismissedAtMs = ts;
  if (note) s.dismissalReasons.push(note);
  s.events.push({ timestampMs: ts, type: "dismissed", windowID: windowId, note });
}
function recordPause(h: History, key: string, untilMs: number | null, ts: number) {
  const s = getOrCreateSummary(h, key);
  s.events.push({ timestampMs: ts, type: "paused", windowID: null, note: untilMs != null ? new Date(untilMs).toISOString() : null });
}
function recordResume(h: History, key: string, ts: number) {
  const s = getOrCreateSummary(h, key);
  s.events.push({ timestampMs: ts, type: "resumed", windowID: null, note: null });
}
function clearDismissal(h: History, key: string, windowId: string, ts: number) {
  const s = getOrCreateSummary(h, key);
  if (s.lastDismissedWindowID === windowId) {
    s.lastDismissedWindowID = null;
    s.lastDismissedAtMs = null;
  }
  s.events.push({ timestampMs: ts, type: "resumed", windowID: windowId, note: null });
}

function webhookEvent(
  kind: WebhookEventKind,
  now: Now,
  dateKey: string,
  windowID: string | null,
  snoozeCount: number | null,
  reason: string | null,
  appId: string | null,
): WebhookEvent {
  return { kind, timestampMs: now.epochMs, dateKey, windowID, snoozeCount, dismissalReason: reason, appId };
}

function clearPrompt(state: CoreState) {
  state.promptShownAtMs = null;
  state.promptWindowId = null;
  state.promptDateKey = null;
}
function closePromptIfShowing(state: CoreState, effects: Effect[]) {
  if (state.mode === "prompting") {
    effects.push({ type: "hideOverlay" });
    clearPrompt(state);
  }
}

function showPrompt(
  state: CoreState,
  window: DowntimeWindow,
  dateKey: string,
  now: Now,
  config: AppConfig,
  effects: Effect[],
  blockedAppId: string | null,
) {
  const summary = summaryFor(state.history, dateKey);
  const quote = config.quotes.length > 0 ? config.quotes[summary.snoozes % config.quotes.length]! : null;
  const escalation = escalationState(summary.snoozes, config, quote);
  recordPrompt(state.history, dateKey, window.id, now.epochMs);
  state.mode = "prompting";
  state.promptShownAtMs = now.epochMs;
  state.promptWindowId = window.id;
  state.promptDateKey = dateKey;
  effects.push({ type: "showOverlay", escalation, window, dateKey, blockedAppId });
}

// ---- event handlers ----
function handleTick(state: CoreState, event: CoreEvent, now: Now, config: AppConfig, effects: Effect[]) {
  if (state.mode === "prompting") {
    const win = activeWindow(now, config);
    const downtimeEnded = win === null;
    const timedOut = state.promptShownAtMs != null && now.epochMs - state.promptShownAtMs >= HOUR_MS;
    if (downtimeEnded || timedOut) {
      if (!downtimeEnded && state.promptDateKey && state.promptWindowId) {
        recordDismissal(state.history, state.promptDateKey, state.promptWindowId, null, now.epochMs);
      }
      effects.push({ type: "hideOverlay" });
      clearPrompt(state);
      state.mode = "idle";
    }
    return;
  }

  if (state.mode === "paused" && state.untilMs != null && now.epochMs >= state.untilMs) {
    state.mode = "idle";
    state.untilMs = null;
  }
  if (state.mode === "snoozed" && state.untilMs != null && now.epochMs >= state.untilMs) {
    state.mode = "idle";
    state.untilMs = null;
  }
  if (state.mode === "paused" || state.mode === "snoozed") return;

  const window = activeWindow(now, config);
  if (!window) {
    state.mode = "idle";
    return;
  }
  const dateKey = dateKeyForMs(window.startMs, now.tzOffsetMin);
  if (summaryFor(state.history, dateKey).lastDismissedWindowID === window.id) {
    state.mode = "idle";
    return;
  }

  const idleSeconds = event.type === "tick" ? event.idleSeconds : undefined;
  const isActive = idleSeconds != null && idleSeconds <= config.idleThresholdMinutes * 60;
  if (state.mode === "idle" || state.mode === "downtimeNormal") {
    state.mode = "downtimeNormal";
    if (isActive) showPrompt(state, window, dateKey, now, config, effects, null);
  }
}

function handleForeground(state: CoreState, appId: string, now: Now, config: AppConfig, effects: Effect[]) {
  if (state.mode === "prompting" || state.mode === "paused" || state.mode === "snoozed") return;
  const window = activeWindow(now, config);
  if (!window) {
    if (state.mode !== "idle") state.mode = "idle";
    return;
  }
  const dateKey = dateKeyForMs(window.startMs, now.tzOffsetMin);
  const summary = summaryFor(state.history, dateKey);
  if (summary.lastDismissedWindowID === window.id) return;

  const blocking = config.appBlocking;
  if (!blocking || !blocking.isEnabled) return;
  const blocked = blocking.blockAllApps || blocking.blockedApps.some((a) => a.isEnabled && a.identifier === appId);
  if (!blocked) return;

  showPrompt(state, window, dateKey, now, config, effects, appId);
  const req = buildWebhookRequest(webhookEvent("blockedAppOpened", now, dateKey, window.id, summary.snoozes, null, appId), config);
  if (req) effects.push({ type: "sendWebhook", request: req });
}

function handleSnooze(state: CoreState, reason: string | null, now: Now, config: AppConfig, effects: Effect[]) {
  if (state.mode !== "prompting" || !state.promptDateKey || !state.promptWindowId) return;
  const dateKey = state.promptDateKey;
  const windowId = state.promptWindowId;
  const untilMs = now.epochMs + config.snoozeMinutes * MIN_MS;
  recordSnooze(state.history, dateKey, windowId, untilMs, now.epochMs);
  const total = summaryFor(state.history, dateKey).snoozes;
  const threshold = config.accountabilityWebhook?.snoozeNotifyThreshold ?? 3;
  if (notifiesOnSnooze(total, threshold)) {
    const req = buildWebhookRequest(webhookEvent("snoozed", now, dateKey, windowId, total, reason, null), config);
    if (req) effects.push({ type: "sendWebhook", request: req });
  }
  effects.push({ type: "notifySnoozed", untilMs });
  effects.push({ type: "hideOverlay" });
  clearPrompt(state);
  state.mode = "snoozed";
  state.untilMs = untilMs;
}

function handleDismiss(state: CoreState, reason: string | null, now: Now, config: AppConfig, effects: Effect[]) {
  if (state.mode !== "prompting" || !state.promptDateKey || !state.promptWindowId) return;
  const dateKey = state.promptDateKey;
  const windowId = state.promptWindowId;
  recordDismissal(state.history, dateKey, windowId, reason, now.epochMs);
  const total = summaryFor(state.history, dateKey).snoozes;
  const req = buildWebhookRequest(webhookEvent("dismissed", now, dateKey, windowId, total, reason, null), config);
  if (req) effects.push({ type: "sendWebhook", request: req });
  effects.push({ type: "hideOverlay" });
  clearPrompt(state);
  state.mode = "idle";
}

function handlePause(state: CoreState, kind: "hour" | "tomorrow", now: Now, config: AppConfig, effects: Effect[]) {
  closePromptIfShowing(state, effects);
  let untilMs: number;
  if (kind === "hour") {
    untilMs = now.epochMs + HOUR_MS;
  } else {
    const startOfTodayLocal = Math.floor(localMs(now) / DAY_MS) * DAY_MS;
    untilMs = startOfTodayLocal + DAY_MS - now.tzOffsetMin * MIN_MS;
  }
  recordPause(state.history, dateKeyForMs(now.epochMs, now.tzOffsetMin), untilMs, now.epochMs);
  state.mode = "paused";
  state.untilMs = untilMs;
}

function handleResume(state: CoreState, now: Now, config: AppConfig, effects: Effect[]) {
  closePromptIfShowing(state, effects);
  state.mode = "idle";
  state.untilMs = null;
  clearPrompt(state);
  recordResume(state.history, dateKeyForMs(now.epochMs, now.tzOffsetMin), now.epochMs);
  const window = activeWindow(now, config);
  if (window) clearDismissal(state.history, dateKeyForMs(window.startMs, now.tzOffsetMin), window.id, now.epochMs);
}

function handleEnforce(state: CoreState, now: Now, config: AppConfig, effects: Effect[]) {
  if (state.mode === "prompting") return;
  closePromptIfShowing(state, effects);
  const dateKey = dateKeyForMs(now.epochMs, now.tzOffsetMin);
  const next = nextDowntimeWindow(now, config);
  const endMs = next ? next.endMs : now.epochMs + HOUR_MS;
  const window: DowntimeWindow = {
    id: `manual-${dateKey}-${now.epochMs}`,
    weekday: weekdayFromDayIndex(dayIndexFromLocalMs(localMs(now))),
    startMs: now.epochMs,
    endMs,
  };
  showPrompt(state, window, dateKey, now, config, effects, null);
}

function handlePermissionRevoked(state: CoreState, now: Now, config: AppConfig, effects: Effect[]) {
  const dateKey = dateKeyForMs(now.epochMs, now.tzOffsetMin);
  const req = buildWebhookRequest(webhookEvent("permissionRevoked", now, dateKey, null, null, null, null), config);
  if (req) effects.push({ type: "sendWebhook", request: req });
}

// ---- status + next-wake (mirror refreshStatus + scheduleNextTick) ----
function finalize(state: CoreState, config: AppConfig, now: Now, effects: Effect[]) {
  const currentWindow = activeWindow(now, config);
  const dateKey = currentWindow ? dateKeyForMs(currentWindow.startMs, now.tzOffsetMin) : dateKeyForMs(now.epochMs, now.tzOffsetMin);
  const snoozeCount = summaryFor(state.history, dateKey).snoozes;

  let icon = "clock";
  let text = "Starting";
  let showsPauseActions = true;
  let showsResumeAction = false;
  let untilMs: number | null = null;

  switch (state.mode) {
    case "prompting":
      icon = "exclamationmark.octagon.fill";
      text = "Enforcement active";
      showsPauseActions = false;
      break;
    case "paused":
      icon = "pause.circle.fill";
      text = "Paused until";
      untilMs = state.untilMs;
      showsPauseActions = false;
      showsResumeAction = true;
      break;
    case "snoozed":
      icon = "moon.zzz.fill";
      text = "Snoozed until";
      untilMs = state.untilMs;
      showsPauseActions = false;
      showsResumeAction = true;
      break;
    case "downtimeNormal":
      icon = "moon.fill";
      text = "In downtime";
      break;
    case "idle":
      if (currentWindow) {
        if (summaryFor(state.history, dateKey).lastDismissedWindowID === currentWindow.id) {
          icon = "checkmark.circle.fill";
          text = "Dismissed for current window";
          showsPauseActions = false;
          showsResumeAction = true;
        } else {
          icon = "moon.fill";
          text = "In downtime";
        }
      } else {
        icon = "sun.max";
        text = "Outside downtime";
      }
      break;
  }

  effects.push({ type: "setStatus", text, icon, snoozeCount, showsPauseActions, showsResumeAction, untilMs });

  let interval: number;
  if (state.mode === "prompting") interval = 5000;
  else if (state.mode === "downtimeNormal") interval = 10000;
  else interval = currentWindow ? 10000 : 60000;
  effects.push({ type: "scheduleWake", atEpochMs: now.epochMs + interval });
}

export function reduce(state: CoreState, event: CoreEvent, now: Now, config: AppConfig): ReduceResult {
  const next = clone(state);
  const effects: Effect[] = [];

  switch (event.type) {
    case "tick":
      handleTick(next, event, now, config, effects);
      break;
    case "foregroundChanged":
      handleForeground(next, event.appId, now, config, effects);
      break;
    case "userSnoozed":
      handleSnooze(next, event.reason ?? null, now, config, effects);
      break;
    case "userDismissed":
      handleDismiss(next, event.reason ?? null, now, config, effects);
      break;
    case "pauseRequested":
      handlePause(next, event.kind, now, config, effects);
      break;
    case "resumeNow":
      handleResume(next, now, config, effects);
      break;
    case "enforceNow":
      handleEnforce(next, now, config, effects);
      break;
    case "permissionRevoked":
      handlePermissionRevoked(next, now, config, effects);
      break;
  }

  finalize(next, config, now, effects);
  return { state: next, effects };
}
