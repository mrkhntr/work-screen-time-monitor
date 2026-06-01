// Mirrors ScheduleEngine.swift, expressed purely in primitives (epoch + tz
// offset) so it needs no timezone database.

import type { AppConfig, DaySchedule } from "./config";
import { scheduleFor, timeMinutes, timeStorage, weekdayName } from "./config";
import type { DowntimeWindow, Now, Weekday } from "./types";
import {
  dateKeyFromDayIndex,
  dayIndexFromLocalMs,
  epochMsFromLocal,
  localMs,
  MS_PER_MINUTE,
  weekdayFromDayIndex,
} from "./time";

export function downtimeWindowForDay(schedule: DaySchedule, dayIndex: number, tzOffsetMin: number): DowntimeWindow {
  const startMin = timeMinutes(schedule.start);
  const endMin = timeMinutes(schedule.end);
  const startMs = epochMsFromLocal(dayIndex, startMin, tzOffsetMin);
  const endDayIndex = endMin <= startMin ? dayIndex + 1 : dayIndex; // overnight / 24h
  const endMs = epochMsFromLocal(endDayIndex, endMin, tzOffsetMin);
  const id = `${dateKeyFromDayIndex(dayIndex)}-${weekdayName(schedule.weekday).toLowerCase()}-${timeStorage(schedule.start)}-${timeStorage(schedule.end)}`;
  return { id, weekday: schedule.weekday, startMs, endMs };
}

function enabledScheduleFor(config: AppConfig, weekday: Weekday): DaySchedule | undefined {
  const s = scheduleFor(config, weekday);
  return s && s.isEnabled ? s : undefined;
}

export function activeWindow(now: Now, config: AppConfig): DowntimeWindow | null {
  const today = dayIndexFromLocalMs(localMs(now));
  for (const offset of [-1, 0]) {
    const dayIndex = today + offset;
    const schedule = enabledScheduleFor(config, weekdayFromDayIndex(dayIndex));
    if (!schedule) continue;
    const w = downtimeWindowForDay(schedule, dayIndex, now.tzOffsetMin);
    if (now.epochMs >= w.startMs && now.epochMs < w.endMs) return w;
  }
  return null;
}

export function nextDowntimeWindow(now: Now, config: AppConfig, limit = 14): DowntimeWindow | null {
  const active = activeWindow(now, config);
  if (active) return active;
  if (limit <= 0) return null;
  const today = dayIndexFromLocalMs(localMs(now));
  for (let off = 0; off < limit; off++) {
    const dayIndex = today + off;
    const schedule = enabledScheduleFor(config, weekdayFromDayIndex(dayIndex));
    if (!schedule) continue;
    const w = downtimeWindowForDay(schedule, dayIndex, now.tzOffsetMin);
    if (w.startMs > now.epochMs) return w;
  }
  return null;
}

export function upcomingWarnings(now: Now, config: AppConfig, limit = 14): { window: DowntimeWindow; warningMs: number }[] {
  if (limit <= 0) return [];
  const out: { window: DowntimeWindow; warningMs: number }[] = [];
  const today = dayIndexFromLocalMs(localMs(now));
  const leadMs = Math.max(0, config.warningLeadMinutes) * MS_PER_MINUTE;
  for (let off = 0; off < limit; off++) {
    const dayIndex = today + off;
    const schedule = enabledScheduleFor(config, weekdayFromDayIndex(dayIndex));
    if (!schedule) continue;
    const w = downtimeWindowForDay(schedule, dayIndex, now.tzOffsetMin);
    const warningMs = w.startMs - leadMs;
    if (warningMs > now.epochMs) out.push({ window: w, warningMs });
  }
  return out;
}
