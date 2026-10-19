import AppKit
import Foundation
@testable import Matcha
import WebKit

/// Pages that play a sound, without network (task 5.10): a WAV file of silence built here, as a `data:` address, in a
/// local page of `TestPages`. Nothing can be heard, but WebKit plays it as a real sound (neither muted nor at zero
/// volume). WebKit only loads media if the web view is in a window: `AudioTestWindow` provides one, offscreen.
@MainActor
enum AudioTestPages {
    /// One second of silence (8 kHz, 8 bits, mono), as a `data:` address.
    static let silence: String = {
        let samples = 8000
        var data = Data("RIFF".utf8)
        func append(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func append(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples))
        data.append(contentsOf: Data("WAVEfmt ".utf8))
        // PCM, 1 channel, 8,000 Hz, 8,000 bytes per second, 1 byte per sample, 8 bits.
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(8000))
        append(UInt32(8000))
        append(UInt16(1))
        append(UInt16(8))
        data.append(contentsOf: Data("data".utf8))
        append(UInt32(samples))
        data.append(Data(repeating: 128, count: samples))
        return "data:audio/wav;base64," + data.base64EncodedString()
    }()

    /// Audio element that plays in a loop as soon as it loads; extra `attributes` (`muted`…).
    static func audio(id: String = "son", attributes: String = "") -> String {
        "<audio id='\(id)' autoplay loop \(attributes) src='\(silence)'></audio>"
    }

    /// Local page `name` that plays a sound in a loop as soon as it loads.
    static func playingPage(_ name: String = "musique", attributes: String = "") -> URL {
        TestPages.url(name, body: audio(attributes: attributes))
    }
}

/// Offscreen window that shows a web view: without a window, WebKit does not load media.
@MainActor
final class AudioTestWindow {
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
    )

    init() {
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    }

    isolated deinit {
        window.orderOut(nil)
    }

    func show(_ webView: WKWebView) {
        webView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        window.contentView = webView
        window.orderFront(nil)
    }
}
