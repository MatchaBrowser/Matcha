import CoreGraphics
import Foundation
@testable import Matcha
import Testing

/// Decoding of icons (audit W8): bitmaps only, never PDF or SVG, off the main thread.
struct FaviconDecoderTests {
    /// 1 × 1 pixel PNG image.
    private static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    @Test func `a bitmap icon is decoded`() async throws {
        let png = try #require(Data(base64Encoded: Self.pngBase64))
        let decoded = try #require(await FaviconDecoder.decode(png))
        #expect(decoded.image.width == 1)
    }

    @Test func `vector and document formats are refused`() throws {
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect width='16' height='16'/></svg>".utf8)
        #expect(FaviconDecoder.decodeNow(svg) == nil)
        #expect(try FaviconDecoder.decodeNow(Self.pdf()) == nil)
        #expect(FaviconDecoder.decodeNow(Data("bonjour".utf8)) == nil)
    }

    /// One-page PDF of 16 × 16 points, drawn in black.
    private static func pdf() throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 16, height: 16)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
