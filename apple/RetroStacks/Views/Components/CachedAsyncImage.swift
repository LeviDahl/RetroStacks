import SwiftUI
import ImageIO
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Like `AsyncImage`, but downsamples to `maxPixelSize` via `ImageIO`
/// (decoding a small bitmap straight from the compressed data, never fully
/// decoding the remote original — the standard, memory-safe pattern, not
/// decode-then-resize) and checks `ImageMemoryCache` first, both off the
/// main actor. A cache hit sets the image with no network round trip and no
/// visible placeholder flash, even though the view itself gets recreated on
/// every switch (e.g. sidebar navigation tearing down and rebuilding a
/// whole screen).
struct CachedAsyncImage<Placeholder: View, Failure: View>: View {
    var url: URL
    var contentMode: ContentMode
    /// Display size in points — drives the downsample target, not just the
    /// final layout frame. Passing the real display size (not the remote
    /// image's native resolution) is what keeps this cache's memory bounded.
    var displaySize: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @State private var image: PlatformImage?
    @State private var loadFailed = false

    /// Fixed 3x buffer for Retina displays rather than reading the real
    /// screen scale — simpler, cross-platform, and a small over-fetch here
    /// is a rounding error next to the original bug (caching full remote
    /// resolution regardless of display size).
    private var maxPixelSize: Int {
        max(1, Int((displaySize * 3).rounded(.up)))
    }

    var body: some View {
        Group {
            if let image {
                platformImage(image).resizable().aspectRatio(contentMode: contentMode)
            } else if loadFailed {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            let target = maxPixelSize
            if let cached = ImageMemoryCache.shared.image(for: url, maxPixelSize: target) {
                image = cached
                return
            }
            // Entirely off the main actor: the network fetch already
            // suspends without blocking, but the ImageIO decode below is
            // synchronous, CPU-bound work that would otherwise run on
            // whatever actor this `.task` closure is isolated to — a View's
            // `.task` is `@MainActor` by default under this project's
            // `-default-isolation=MainActor` build flag.
            let result = await ImageDownsampler.fetch(url: url, maxPixelSize: target)
            guard let result else {
                loadFailed = true
                return
            }
            ImageMemoryCache.shared.set(result.image, for: url, maxPixelSize: target, costBytes: result.costBytes)
            image = result.image
        }
    }

    private func platformImage(_ img: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: img)
        #elseif canImport(AppKit)
        Image(nsImage: img)
        #endif
    }
}

/// Non-generic on purpose: called from a detached closure inside the generic
/// `CachedAsyncImage`, where `Self.` would capture the non-`Sendable`
/// `Placeholder`/`Failure` metatypes.
nonisolated enum ImageDownsampler {
    /// Network fetch + ImageIO decode, off the main actor (`@concurrent`).
    @concurrent
    static func fetch(url: URL, maxPixelSize: Int) async -> (image: PlatformImage, costBytes: Int)? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return downsample(data: data, maxPixelSize: maxPixelSize)
    }

    /// Not `private` — this is the one piece of the real memory bug fix
    /// (see `ImageMemoryCache`'s doc comment) that's pure, testable logic
    /// without a network round trip; exercised directly by
    /// `CachedAsyncImageTests`, not just read.
    static func downsample(data: Data, maxPixelSize: Int) -> (image: PlatformImage, costBytes: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let costBytes = cgImage.bytesPerRow * cgImage.height
        #if canImport(UIKit)
        let image = UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
        return (image, costBytes)
    }
}
