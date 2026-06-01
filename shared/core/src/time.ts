// Pure local-time math from { epochMs, tzOffsetMin } — no Intl, no timezone DB.
// Calendar extraction uses the built-in Date UTC getters (core ECMAScript,
// available in both JavaScriptCore and QuickJS); we never use Date's local
// (timezone-dependent) methods.

import type { Now, Weekday } from "./types";

export const MS_PER_MINUTE = 60_000;
export const MS_PER_DAY = 86_400_000;
export const MINUTES_PER_DAY = 1440;

/** Local milliseconds-since-epoch (wall clock treated as if UTC). */
export function localMs(now: Now): number {
  return now.epochMs + now.tzOffsetMin * MS_PER_MINUTE;
}

/** Whole local days since 1970-01-01 for a local-ms value. */
export function dayIndexFromLocalMs(ms: number): number {
  return Math.floor(ms / MS_PER_DAY);
}

export function minutesOfDayFromLocalMs(ms: number): number {
  const within = ms - dayIndexFromLocalMs(ms) * MS_PER_DAY;
  return Math.floor(within / MS_PER_MINUTE);
}

function utcDateForDayIndex(dayIndex: number): Date {
  return new Date(dayIndex * MS_PER_DAY);
}

/** Sunday=1 ... Saturday=7 (matches Swift Weekday). */
export function weekdayFromDayIndex(dayIndex: number): Weekday {
  return (utcDateForDayIndex(dayIndex).getUTCDay() + 1) as Weekday;
}

/** "YYYY-MM-DD" for a local day index. */
export function dateKeyFromDayIndex(dayIndex: number): string {
  const d = utcDateForDayIndex(dayIndex);
  const pad = (n: number, w: number) => String(n).padStart(w, "0");
  return `${pad(d.getUTCFullYear(), 4)}-${pad(d.getUTCMonth() + 1, 2)}-${pad(d.getUTCDate(), 2)}`;
}

/** "YYYY-MM-DD" for the local day containing `now`. */
export function dateKey(now: Now): string {
  return dateKeyFromDayIndex(dayIndexFromLocalMs(localMs(now)));
}

/** Convert a local day index + minutes-of-day back to epoch milliseconds. */
export function epochMsFromLocal(dayIndex: number, minutesOfDay: number, tzOffsetMin: number): number {
  return dayIndex * MS_PER_DAY + minutesOfDay * MS_PER_MINUTE - tzOffsetMin * MS_PER_MINUTE;
}
