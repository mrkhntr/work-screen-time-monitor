import XCTest
@testable import WorkScreenTimeCore

final class ConfirmationPhraseMatcherTests: XCTestCase {
    func testMatchesIgnoringWhitespacePunctuationAndCapitalization() {
        XCTAssertTrue(ConfirmationPhraseMatcher.matches(
            "  \"REST\"--belongs, on the calendar!!! 🌙 ",
            phrase: "Rest belongs on the calendar."
        ))
    }

    func testMatchesUsingOnlyLettersAToZ() {
        XCTAssertEqual(
            ConfirmationPhraseMatcher.normalized("A1 b_2 C! é. \"\" '' “” 🌙"),
            "abc"
        )
    }

    func testDoesNotMatchDifferentLetters() {
        XCTAssertFalse(ConfirmationPhraseMatcher.matches(
            "rest belongs at the keyboard",
            phrase: "Rest belongs on the calendar."
        ))
    }
}
