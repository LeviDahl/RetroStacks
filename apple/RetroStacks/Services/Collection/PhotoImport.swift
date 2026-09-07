import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Photo bytes for `CollectionItem.photoData`. Picked images are re-encoded to a
/// bounded JPEG so a few phone photos don't bloat the SwiftData store or the
/// base64 in a `CollectionArchive` export. Pure ImageIO — no UIKit/AppKit fork.
nonisolated enum PhotoImport {
    /// Longest edge, in pixels, of a stored photo.
    static let maxPixelSize = 1600
    static let maxPhotosPerItem = 8

    static func normalizedJPEG(from data: Data, quality: Double = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest, cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

extension Image {
    /// Best-effort `Image` from raw encoded bytes, cross-platform.
    init?(photoData data: Data) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.init(decorative: cgImage, scale: 1)
    }
}
