import Foundation
@testable import Matcha
import Testing

/// Parsing the sound script's messages (task 5.10): any malformed body is ignored.
struct PageAudioReportTests {
    @Test func `reads a playing document`() {
        let report = PageAudioReport(messageBody: ["frame": "k3j2h1", "audible": true])
        #expect(report == PageAudioReport(frame: "k3j2h1", isAudible: true, isGone: false))
    }

    @Test func `reads a document that goes away`() {
        let report = PageAudioReport(messageBody: ["frame": "k3j2h1", "audible": false, "gone": true])
        #expect(report == PageAudioReport(frame: "k3j2h1", isAudible: false, isGone: true))
    }

    /// WebKit gives JavaScript booleans as `NSNumber`, in an `NSDictionary`.
    @Test func `reads the objects WebKit gives`() {
        let body: NSDictionary = ["frame": NSString(string: "abc"), "audible": NSNumber(value: true), "gone": NSNumber(value: false)]
        #expect(PageAudioReport(messageBody: body) == PageAudioReport(frame: "abc", isAudible: true))
    }

    @Test func `ignores malformed messages`() {
        let lists: [Any] = ["audible", ["audible", true] as [Any]]
        let dictionaries: [[String: Any]] = [
            [:],
            ["audible": true],
            ["frame": "abc"],
            ["frame": "", "audible": true],
            ["frame": String(repeating: "a", count: 65), "audible": true],
            ["frame": 42, "audible": true],
            ["frame": "abc", "audible": "yes"],
            ["frame": "abc", "audible": NSNull()],
            ["frame": "abc", "audible": true, "gone": "no"],
        ]
        let bodies = lists + dictionaries.map { $0 as Any }
        for body in bodies {
            #expect(PageAudioReport(messageBody: body) == nil, "\(body)")
        }
    }

    @Test func `accepts the longest frame identifier`() {
        let frame = String(repeating: "a", count: PageAudioReport.maximumFrameLength)
        #expect(PageAudioReport(messageBody: ["frame": frame, "audible": false])?.frame == frame)
    }
}
