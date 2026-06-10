import UIKit

/// Turns a picked image into a small, square avatar JPEG before it ever touches
/// the SwiftData store or syncs as a CKAsset. Raw camera photos are multi-megabyte
/// — storing those would bloat the local store and make sync crawl — so every
/// avatar write funnels through here first.
enum ImageDownscale {
    /// Center-crops to a square, resizes to `side` points (aspect-fill), and
    /// re-encodes as JPEG. Returns nil if the data isn't a decodable image.
    static func avatar(from data: Data, side: CGFloat = 512, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return avatar(from: image, side: side, quality: quality)
    }

    static func avatar(from image: UIImage, side: CGFloat = 512, quality: CGFloat = 0.8) -> Data? {
        let target = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1            // `side` is already in pixels; don't multiply by screen scale
        format.opaque = true

        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // Aspect-fill: scale so the shorter edge covers the square, then center.
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (target.width - drawn.width) / 2,
                                 y: (target.height - drawn.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
