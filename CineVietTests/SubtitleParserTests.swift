import XCTest
@testable import CineViet

final class SubtitleParserTests: XCTestCase {
    func testParsesSRTCue() {
        let cues = SubtitleParser.parse("1\n00:00:01,000 --> 00:00:02,500\nXin chào", format: "srt")
        XCTAssertEqual(cues.first?.text, "Xin chào")
        XCTAssertEqual(try XCTUnwrap(cues.first).start, 1, accuracy: 0.01)
    }
}
