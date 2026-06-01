// Mirrors ScheduleEngine.escalationState (ScheduleEngine.swift).

import type { AppConfig } from "./config";
import type { EscalationState } from "./types";

function nilIfBlank(s: string | null | undefined): string | null {
  if (s == null) return null;
  const t = s.replace(/^\s+|\s+$/g, "");
  return t.length ? t : null;
}

function minutesDescription(minutes: number): string {
  return minutes === 1 ? "1 more minute" : `${minutes} more minutes`;
}

function reachedThreshold(count: number, threshold: number): boolean {
  return count >= Math.max(0, threshold);
}

export function escalationState(snoozeCountRaw: number, config: AppConfig, quote: string | null | undefined): EscalationState {
  const snoozeCount = Math.max(0, snoozeCountRaw);
  const q = nilIfBlank(quote);
  let title: string;
  let message: string;

  switch (snoozeCount) {
    case 0:
      title = "Time to stop working";
      message = q ?? "You have done enough for today.";
      break;
    case 1:
      title = `You already asked for ${minutesDescription(Math.max(config.snoozeMinutes, 1))}`;
      message = "Close the loop and protect the rest of your night.";
      break;
    case 2:
      title = "This is the second snooze";
      message = "Hold to unlock the next action before continuing.";
      break;
    default:
      title = "You are past the boundary you set";
      message = "To snooze or dismiss, unlock the action and write why continuing makes sense.";
      break;
  }

  const e = config.escalation;
  return {
    snoozeCount,
    title,
    message,
    confirmationPhrase: q ?? e.confirmationPhrase,
    requiresHold: reachedThreshold(snoozeCount, e.holdRequiredAtSnoozeCount),
    requiresPhrase: reachedThreshold(snoozeCount, e.phraseRequiredAtSnoozeCount),
    requiresReason: reachedThreshold(snoozeCount, e.reasonRequiredAtSnoozeCount),
  };
}
