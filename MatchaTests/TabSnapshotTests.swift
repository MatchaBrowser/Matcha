import CoreGraphics
import Foundation
import ImageIO
@testable import Matcha
import Testing
import WebKit

/// Capture d'une page avant sa mise en veille (tâche 5.6) : taille réduite, JPEG, capture d'une vue hors fenêtre.
@MainActor
struct TabSnapshotTests {
    /// Image unie de `width` × `height` pixels.
    private func image(width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Taille en pixels d'une image JPEG : [largeur, hauteur].
    private func pixelSize(of data: Data) throws -> [Int] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return [image.width, image.height]
    }

    /// Taille gardée pour une capture : [largeur, hauteur].
    private func reduced(_ width: Int, _ height: Int, maximumWidth: Int = TabSnapshot.maximumPixelWidth) -> [Int] {
        let size = TabSnapshot.pixelSize(width: width, height: height, maximumWidth: maximumWidth)
        return [size.width, size.height]
    }

    @Test func `large captures are scaled down to the maximum width, keeping proportions`() {
        #expect(reduced(2400, 1600) == [1200, 800])
        #expect(reduced(2880, 1800, maximumWidth: 1000) == [1000, 625])
        #expect(reduced(5000, 1) == [1200, 1])
    }

    @Test func `small captures are never enlarged`() {
        #expect(reduced(800, 600) == [800, 600])
        #expect(reduced(1200, 900) == [1200, 900])
        #expect(reduced(0, 0) == [1, 1])
    }

    @Test func `jpeg data is small and has the reduced size`() throws {
        let data = try #require(TabSnapshot.jpegData(from: image(width: 2400, height: 1600)))
        #expect(try pixelSize(of: data) == [1200, 800])
        // Une image unie se compresse très bien ; une vraie page pèse quelques dizaines de kilo-octets.
        #expect(data.count < 100_000)
        #expect(data.starts(with: [0xFF, 0xD8]))
    }

    /// La vue d'un onglet caché n'est dans aucune fenêtre : WebKit la capture quand même.
    @Test func `a web view outside any window can be captured`() async throws {
        let tab = BrowserTab(configuration: TestPages.configuration())
        tab.load(TestPages.url("capture", body: "<div style='background:red;height:2000px'>Bonjour</div>"))
        try await waitUntil { tab.title == "capture" && !tab.isLoading }
        let webView = tab.loadedWebView
        #expect(webView.window == nil)
        // Jamais affichée : pas de taille, pas de capture.
        #expect(await TabLifecycleProbes.snapshot(of: webView, url: tab.url) == nil)

        webView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let snapshot = try #require(await TabLifecycleProbes.snapshot(of: webView, url: tab.url))
        #expect(snapshot.url == tab.url)
        #expect(snapshot.pageWidth == 800)
        let size = try pixelSize(of: snapshot.data)
        #expect(size[0] <= TabSnapshot.maximumPixelWidth)
        #expect(size[0] * 600 == size[1] * 800)
    }

    /// Une page affichée à une autre largeur est mise en page autrement : sa capture ne la couvre pas.
    @Test func `the cover only fits a page of about the same width`() {
        #expect(SuspendedPageCover.fits(pageWidth: 800, in: 800))
        #expect(SuspendedPageCover.fits(pageWidth: 760, in: 800))
        #expect(SuspendedPageCover.fits(pageWidth: 880, in: 800))
        #expect(!SuspendedPageCover.fits(pageWidth: 400, in: 800))
        #expect(!SuspendedPageCover.fits(pageWidth: 1200, in: 800))
        #expect(!SuspendedPageCover.fits(pageWidth: 800, in: 0))
    }
}
