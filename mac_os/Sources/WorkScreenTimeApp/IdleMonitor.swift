import Foundation
import IOKit

struct IdleMonitor {
    func secondsSinceLastInput() -> TimeInterval {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else {
            return 0
        }
        defer {
            IOObjectRelease(service)
        }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any],
              let idleTime = properties["HIDIdleTime"] as? NSNumber else {
            return 0
        }

        return idleTime.doubleValue / 1_000_000_000
    }
}
