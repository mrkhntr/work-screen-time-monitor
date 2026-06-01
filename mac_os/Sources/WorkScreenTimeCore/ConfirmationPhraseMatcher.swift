import Foundation

public enum ConfirmationPhraseMatcher {
    public static func matches(_ input: String, phrase: String) -> Bool {
        normalized(input) == normalized(phrase)
    }

    public static func normalized(_ value: String) -> String {
        value
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { (97...122).contains($0.value) }
            .map(String.init)
            .joined()
    }
}
