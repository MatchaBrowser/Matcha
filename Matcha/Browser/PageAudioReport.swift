import Foundation

/// Message from the sound script (`PageAudioScript`, task 5.10) for a document of the page: the main frame or an
/// iframe. Expected body: `{frame: String, audible: Bool, gone: Bool?}`; any other body is ignored.
nonisolated struct PageAudioReport: Equatable, Sendable {
    /// Maximum length of a document's identifier (the script draws a short one at random).
    static let maximumFrameLength = 64

    /// Identifier of the document, drawn at random by the script when it loads.
    let frame: String
    /// An audio or video element of the document plays with sound (neither muted nor at zero volume).
    let isAudible: Bool
    /// The document goes away (`pagehide`): its sound stops with it.
    let isGone: Bool

    init(frame: String, isAudible: Bool, isGone: Bool = false) {
        self.frame = frame
        self.isAudible = isAudible
        self.isGone = isGone
    }

    /// Reads the body of a `WKScriptMessage`; nil if it is malformed.
    init?(messageBody body: Any) {
        guard let fields = body as? [String: Any],
              let frame = fields["frame"] as? String,
              !frame.isEmpty, frame.count <= Self.maximumFrameLength,
              let isAudible = fields["audible"] as? Bool
        else {
            return nil
        }
        let gone = fields["gone"]
        guard gone == nil || gone is Bool else {
            return nil
        }
        self.init(frame: frame, isAudible: isAudible, isGone: gone as? Bool ?? false)
    }
}
