import Foundation
import Testing

@testable import RetroStacks

/// `makeSlug` is the one piece of `CustomCatalogItemService` that's pure
/// logic (everything else is a network call) — worth locking down on its
/// own since a bad slug either collides (no suffix) or breaks the catalog's
/// slug conventions (unescaped punctuation).
struct CustomCatalogItemServiceTests {
    @Test func buildsAReadableSlugFromPlatformNameAndVariant() {
        let slug = CustomCatalogItemService.makeSlug(
            platformSlug: "nes", name: "The Legend of Zelda", variant: "5-Screw"
        )
        #expect(slug.hasPrefix("nes-the-legend-of-zelda-5-screw-"))
        // A short random suffix after the base — not empty, not the base itself.
        #expect(slug.count > "nes-the-legend-of-zelda-5-screw-".count)
    }

    @Test func omitsTheVariantSegmentWhenThereIsNone() {
        let slug = CustomCatalogItemService.makeSlug(platformSlug: "nes", name: "2048", variant: nil)
        #expect(slug.hasPrefix("nes-2048-"))
    }

    @Test func blankVariantIsTreatedTheSameAsNoVariant() {
        let slug = CustomCatalogItemService.makeSlug(platformSlug: "nes", name: "2048", variant: "   ")
        #expect(slug.hasPrefix("nes-2048-"))
    }

    @Test func stripsPunctuationAndCollapsesRuns() {
        let slug = CustomCatalogItemService.makeSlug(
            platformSlug: "nes", name: "Kirby's Adventure!!  (USA)", variant: nil
        )
        #expect(slug.hasPrefix("nes-kirby-s-adventure-usa-"))
        #expect(!slug.contains("--"))
    }

    @Test func twoCallsWithTheSameInputsProduceDifferentSlugs() {
        let first = CustomCatalogItemService.makeSlug(platformSlug: "nes", name: "2048", variant: nil)
        let second = CustomCatalogItemService.makeSlug(platformSlug: "nes", name: "2048", variant: nil)
        #expect(first != second)
    }
}
