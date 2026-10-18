import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Capture d'une page avant sa mise en veille (tâche 5.6), compressée en JPEG pour peser peu en mémoire (quelques
/// dizaines de kilo-octets), avec l'adresse de la page capturée (elle ne couvre jamais une autre page) et la largeur
/// de la vue en points (elle ne couvre pas une page affichée à une autre largeur, mise en page différente).
nonisolated struct TabSnapshot: Sendable {
    /// Largeur maximale de l'image gardée, en pixels : une capture Retina est réduite de moitié environ.
    static let maximumPixelWidth = 1200
    /// Qualité JPEG : la capture n'est montrée qu'un instant, pendant le rechargement de la page.
    static let jpegQuality = 0.7

    let data: Data
    let url: URL?
    /// Largeur de la vue capturée, en points.
    let pageWidth: Double

    /// Taille de l'image gardée pour une capture de `width` × `height` pixels : même proportion, largeur au plus
    /// `maximumWidth`, jamais agrandie, au moins un pixel de côté.
    static func pixelSize(width: Int, height: Int, maximumWidth: Int = maximumPixelWidth) -> (width: Int, height: Int) {
        guard width > maximumWidth, width > 0 else {
            return (max(width, 1), max(height, 1))
        }
        let scaledHeight = (Double(height) * Double(maximumWidth) / Double(width)).rounded()
        return (maximumWidth, max(Int(scaledHeight), 1))
    }

    /// Image réduite (`pixelSize`) puis compressée en JPEG ; nil si l'image ne peut pas être dessinée ou encodée.
    static func jpegData(from image: CGImage, maximumWidth: Int = maximumPixelWidth, quality: Double = jpegQuality) -> Data? {
        let size = pixelSize(width: image.width, height: image.height, maximumWidth: maximumWidth)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: size.width,
                  height: size.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
              )
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
