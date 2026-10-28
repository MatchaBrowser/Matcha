import Foundation

extension BrowserTab {
    /// The page's document goes away (web view released, process terminated): its sound stops (icon included) and it
    /// is no longer translated (task 9.2).
    func endPageActivity() {
        audio.reset()
        translation.reset()
    }
}
