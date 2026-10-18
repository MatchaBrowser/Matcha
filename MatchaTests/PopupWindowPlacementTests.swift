import CoreGraphics
import Foundation
@testable import Matcha
import Testing

/// Fenêtres de connexion (tâche 5.8) : quand une fenêtre ouverte par une page en devient une, sa taille et sa place.
@MainActor
struct PopupWindowPlacementTests {
    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func `a size given by the page opens a sign-in window`() {
        #expect(PopupWindowFeatures(width: 500, height: 600).opensPopupWindow)
        #expect(PopupWindowFeatures(width: 500).opensPopupWindow)
        #expect(PopupWindowFeatures(height: 600).opensPopupWindow)
    }

    /// `target=_blank`, `window.open(url)`, `noopener` : rien. Une taille nulle veut dire « par défaut » pour WebKit.
    @Test func `no usable size keeps a tab`() {
        #expect(!PopupWindowFeatures().opensPopupWindow)
        #expect(!PopupWindowFeatures(width: 0, height: 0).opensPopupWindow)
        #expect(!PopupWindowFeatures(width: -10, height: .nan).opensPopupWindow)
        #expect(!PopupWindowFeatures(width: .infinity).opensPopupWindow)
        #expect(PopupWindowFeatures(width: 0, height: 0) == PopupWindowFeatures())
    }

    @Test func `the size is read from WebKit's window features`() {
        #expect(PopupWindowFeatures(FakeWindowFeatures(width: 480, height: 640)) == PopupWindowFeatures(width: 480, height: 640))
        #expect(PopupWindowFeatures(FakeWindowFeatures(width: 480)) == PopupWindowFeatures(width: 480))
        #expect(!PopupWindowFeatures(FakeWindowFeatures()).opensPopupWindow)
    }

    @Test func `the page gets the requested size, the default for a missing one, at least the minimum`() {
        #expect(PopupWindowPlacement.pageSize(for: PopupWindowFeatures(width: 500, height: 600)) == CGSize(width: 500, height: 600))
        #expect(PopupWindowPlacement.pageSize(for: PopupWindowFeatures(width: 450)) == CGSize(width: 450, height: 600))
        #expect(PopupWindowPlacement.pageSize(for: PopupWindowFeatures(height: 700)) == CGSize(width: 600, height: 700))
        #expect(PopupWindowPlacement.pageSize(for: PopupWindowFeatures(width: 1, height: 1)) == CGSize(width: 320, height: 300))
        #expect(PopupWindowPlacement.pageSize(for: PopupWindowFeatures(width: 500.4, height: 599.6)) == CGSize(width: 500, height: 600))
    }

    @Test func `the window is centered on its opener`() {
        let opener = CGRect(x: 100, y: 125, width: 1000, height: 700)
        let frame = PopupWindowPlacement.frame(size: CGSize(width: 500, height: 630), opener: opener, in: screen)
        #expect(frame == CGRect(x: 350, y: 160, width: 500, height: 630))
    }

    @Test func `without an opener it is centered on the screen`() {
        let frame = PopupWindowPlacement.frame(size: CGSize(width: 500, height: 630), opener: nil, in: screen)
        #expect(frame == CGRect(x: 470, y: 148, width: 500, height: 630))
    }

    @Test func `a window larger than the screen is reduced to it`() {
        let frame = PopupWindowPlacement.frame(size: CGSize(width: 2000, height: 1200), opener: nil, in: screen)
        #expect(frame == screen)
    }

    /// Fenêtre d'origine contre un bord (ou en partie hors de l'écran) : la fenêtre de connexion glisse pour tenir.
    @Test func `the window stays inside the screen`() {
        let left = PopupWindowPlacement.frame(
            size: CGSize(width: 500, height: 630),
            opener: CGRect(x: -300, y: 500, width: 400, height: 600),
            in: screen,
        )
        #expect(left == CGRect(x: 0, y: 270, width: 500, height: 630))
        let top = PopupWindowPlacement.frame(
            size: CGSize(width: 500, height: 630),
            opener: CGRect(x: 1200, y: 800, width: 400, height: 300),
            in: screen,
        )
        #expect(top == CGRect(x: 940, y: 270, width: 500, height: 630))
    }

    /// Second écran à droite du premier, plus bas : les coordonnées d'AppKit s'y prolongent.
    @Test func `the window opens on the screen of its opener`() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let opener = CGRect(x: 1600, y: -100, width: 1200, height: 800)
        let frame = PopupWindowPlacement.frame(size: CGSize(width: 600, height: 500), opener: opener, in: second)
        #expect(frame == CGRect(x: 1900, y: 50, width: 600, height: 500))
    }
}
