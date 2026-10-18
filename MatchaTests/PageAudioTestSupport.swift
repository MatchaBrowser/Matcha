import AppKit
import Foundation
@testable import Matcha
import WebKit

/// Pages qui jouent un son, sans réseau (tâche 5.10) : un fichier WAV de silence fabriqué ici, en adresse `data:`, dans
/// une page locale de `TestPages`. On n'entend rien, mais WebKit le joue comme un vrai son (ni coupé, ni à volume nul).
/// WebKit ne charge un média que si la vue web est dans une fenêtre : `AudioTestWindow` en donne une, hors de l'écran.
@MainActor
enum AudioTestPages {
    /// Une seconde de silence (8 kHz, 8 bits, mono), en adresse `data:`.
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
        // PCM, 1 canal, 8 000 Hz, 8 000 octets par seconde, 1 octet par échantillon, 8 bits.
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

    /// Élément audio qui joue en boucle dès le chargement ; `attributes` en plus (`muted`…).
    static func audio(id: String = "son", attributes: String = "") -> String {
        "<audio id='\(id)' autoplay loop \(attributes) src='\(silence)'></audio>"
    }

    /// Page locale `name` qui joue un son en boucle dès son chargement.
    static func playingPage(_ name: String = "musique", attributes: String = "") -> URL {
        TestPages.url(name, body: audio(attributes: attributes))
    }
}

/// Fenêtre hors de l'écran qui montre une vue web : sans fenêtre, WebKit ne charge pas les médias.
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
