// Mirrors WorkScreenTimeCore/AccountabilityTrigger.swift.

/** Whether snoozing notifies the contact, given the day's total snooze count after this snooze. */
export function notifiesOnSnooze(totalSnoozesAfter: number, threshold: number): boolean {
  return totalSnoozesAfter >= Math.max(1, threshold);
}
