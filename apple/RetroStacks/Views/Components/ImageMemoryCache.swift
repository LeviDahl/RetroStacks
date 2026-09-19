import Foundation
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// App-wide in-memory image cache, keyed by URL *and* the pixel size it was
/// decoded at. Exists specifically so `ItemThumbnail` doesn't visibly
/// reload/re-flash images every time its *view* identity is recreated — a
/// plain `AsyncImage` re-runs its whole fetch-and-phase-transition on every
/// fresh instantiation regardless of whether the underlying bytes are
/// already in `URLCache`, since it has no persistent identity of its own
/// beyond whatever its parent view tree gives it.
///
/// **Real bug, found live 2026-09-19 from the user's own report** ("gets
/// progressively worse... Catalog completely locked up... indicative of a
/// memory leak"): the first version of this cache stored whatever
/// `CachedAsyncImage` decoded — the *full* remote resolution (these come
/// from Wikimedia/Libretro, commonly ~800px wide) — for thumbnails
/// typically rendered at 52-120pt, and bounded itself with `countLimit`
/// (object count) instead of actual memory size. An 800×800 decoded RGBA
/// bitmap is ~2.5MB; with Browse Catalog alone at 16,000+ items, that's
/// unbounded growth into real gigabytes, not a technical leak (`NSCache`
/// does evict under memory pressure) but practically indistinguishable
/// from one — progressively worse, eventually a full lockup, exactly as
/// reported. Fixed two ways: `CachedAsyncImage` now downsamples to the
/// actual requested display size via `ImageIO` *before* this cache ever
/// sees the result (a small bitmap decoded straight from compressed data,
/// never fully decoding the large original at all — the standard,
/// Apple-recommended pattern, not decode-then-resize), and this cache now
/// tracks real byte cost via `NSCache.totalCostLimit`, not object count.
///
/// Deliberately in-memory only, not persisted to disk — smoothing out
/// repeat navigation *within a session* is the whole point; `URLCache`
/// already covers the byte-level offline/relaunch case.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    /// A url+size pair — the same remote image decoded at two different
    /// display sizes (a small row thumbnail vs. a large detail header) are
    /// deliberately two different cache entries, not one, since a
    /// downsampled-small bitmap can't be upscaled back to a sharp large one.
    private nonisolated struct Key: Hashable {
        var url: URL
        var maxPixelSize: Int
    }

    private final class KeyBox: NSObject, @unchecked Sendable {
        let key: Key
        init(_ key: Key) { self.key = key }
        override nonisolated var hash: Int { key.hashValue }
        override nonisolated func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private let cache: NSCache<KeyBox, PlatformImage> = {
        let cache = NSCache<KeyBox, PlatformImage>()
        // Real byte budget, not object count — 80MB comfortably covers
        // hundreds of small downsampled thumbnails without the unbounded
        // full-resolution growth that caused the original lockup.
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    private init() {}

    func image(for url: URL, maxPixelSize: Int) -> PlatformImage? {
        cache.object(forKey: KeyBox(Key(url: url, maxPixelSize: maxPixelSize)))
    }

    func set(_ image: PlatformImage, for url: URL, maxPixelSize: Int, costBytes: Int) {
        cache.setObject(image, forKey: KeyBox(Key(url: url, maxPixelSize: maxPixelSize)), cost: costBytes)
    }
}
