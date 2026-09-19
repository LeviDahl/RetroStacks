import Foundation
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@testable import RetroStacks

/// Real bug, user-reported 2026-09-19: the first version of `ItemThumbnail`'s
/// image cache stored whatever was decoded at full remote resolution
/// (commonly ~800px from Wikimedia/Libretro) regardless of the ~56-120pt
/// display size, with only an `NSCache` object-count limit, not a memory
/// one — unbounded growth that got "progressively worse" and eventually
/// locked up on Browse Catalog (16,000+ items). Locks down that
/// `ImageDownsampler.downsample` actually produces a small bitmap, not the
/// original resolution.
struct CachedAsyncImageTests {
    /// A real PNG, not a mock — draws an oversized bitmap and encodes it,
    /// so this exercises the actual `ImageIO` decode path.
    private func syntheticPNGData(pixelSize: Int) -> Data {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))
        let image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        }
        return image.pngData()!
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
        #endif
    }

    @Test func downsampleShrinksAnOversizedImageToRoughlyTheRequestedSize() throws {
        let data = syntheticPNGData(pixelSize: 800)

        let result = try #require(ImageDownsampler.downsample(data: data, maxPixelSize: 168))

        #if canImport(UIKit)
        let pixelWidth = result.image.size.width * result.image.scale
        #elseif canImport(AppKit)
        let rep = result.image.representations.first
        let pixelWidth = CGFloat(rep?.pixelsWide ?? Int(result.image.size.width))
        #endif

        // Real requirement: materially smaller than the 800px original, not
        // exactly 168 (ImageIO rounds to the nearest sensible dimension).
        #expect(pixelWidth <= 200)
        #expect(pixelWidth < 800)
    }

    @Test func downsampleCostReflectsTheSmallDecodedSizeNotTheOriginal() throws {
        let data = syntheticPNGData(pixelSize: 800)

        let result = try #require(ImageDownsampler.downsample(data: data, maxPixelSize: 168))

        // An 800x800 RGBA bitmap would cost ~2.5MB; a ~168px one should be a
        // small fraction of that — the whole point of downsampling before
        // caching, not after.
        #expect(result.costBytes < 300_000)
    }

    @Test func downsampleReturnsNilForGarbageData() {
        let result = ImageDownsampler.downsample(data: Data([0, 1, 2, 3]), maxPixelSize: 168)
        #expect(result == nil)
    }
}
