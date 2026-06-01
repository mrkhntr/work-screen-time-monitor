import Foundation

public enum AccountabilityTrigger {
    /// Default day's-total snooze count at which snoozing begins notifying the accountability contact.
    public static let defaultSnoozeNotifyThreshold = 3

    /// Whether snoozing notifies the accountability contact, given the day's total snooze count after this snooze.
    public static func notifiesOnSnooze(totalSnoozesAfter total: Int, threshold: Int) -> Bool {
        total >= max(1, threshold)
    }
}
