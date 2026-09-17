import Foundation
import Testing

@testable import RetroStacks

/// `SupabaseCatalogItemRow` is the wire shape for `public.catalog_items` —
/// decodes a realistic PostgREST payload directly, the same reasoning as
/// `SupabaseCollectionRowTests`: `.exactKeys` (not `.convertFromSnakeCase`)
/// is what this type depends on, and that's only actually exercised once
/// real JSON round-trips through it, not by constructing the struct by hand.
struct SupabaseCatalogItemRowTests {
    private static let realisticRow = """
    [
      {
        "id": "8C9E2B0A-6A5E-4B8A-9C1E-1B2C3D4E5F60",
        "slug": "snes-chrono-trigger",
        "owner_user_id": null,
        "platform_slug": "snes",
        "kind": "game",
        "name": "Chrono Trigger",
        "variant": null,
        "release_year_na": 1995,
        "manufacturer_or_publisher": "Square",
        "developer": "Square",
        "genre": "RPG",
        "upc": null,
        "summary": "Dream-team JRPG.",
        "image_name": null,
        "image_url_string": "https://example.com/ct.png",
        "image_credit": "Box art",
        "image_license": "Publisher artwork",
        "estimated_value_loose": null,
        "estimated_value_complete": null,
        "estimated_value_sealed": null,
        "estimated_value_graded": null,
        "sales_volume_yearly": null,
        "price_guide_provider_id": null,
        "price_guide_updated_at": null,
        "submitted_for_public": false,
        "updated_at": "2026-09-17T00:00:00Z",
        "deleted_at": null
      }
    ]
    """

    @Test func decodesARealisticCatalogItemRow() throws {
        let data = try #require(Self.realisticRow.data(using: .utf8))
        let rows = try JSONDecoder.exactKeys.decode([SupabaseCatalogItemRow].self, from: data)
        let row = try #require(rows.first)

        #expect(row.slug == "snes-chrono-trigger")
        #expect(row.platformSlug == "snes")
        #expect(row.developer == "Square")
        #expect(row.genre == "RPG")
        #expect(row.ownerUserID == nil)

        // The actual point: extra columns this type doesn't model yet
        // (estimated_value_*, submitted_for_public, etc.) don't break
        // decoding — Decodable ignores unknown keys by default, but worth
        // locking down given this row shape will keep growing.
        let feedItem = row.asFeedItem
        #expect(feedItem.slug == row.slug)
        #expect(feedItem.name == "Chrono Trigger")
        #expect(feedItem.imageURL == "https://example.com/ct.png")
        #expect(feedItem.ownerUserID == nil)
    }

    /// A private row — `owner_user_id` set, the one field that tells the app
    /// apart a "mine" entry (`CatalogItem.ownerUserID`) from a public one.
    @Test func decodesAPrivateRowsOwner() throws {
        let ownerID = UUID()
        let json = """
        [
          {
            "slug": "nes-zelda-5-screw-abc123",
            "owner_user_id": "\(ownerID.uuidString)",
            "platform_slug": "nes",
            "kind": "game",
            "name": "The Legend of Zelda",
            "variant": "5-Screw",
            "summary": ""
          }
        ]
        """
        let data = try #require(json.data(using: .utf8))
        let rows = try JSONDecoder.exactKeys.decode([SupabaseCatalogItemRow].self, from: data)
        let row = try #require(rows.first)

        #expect(row.ownerUserID == ownerID)
        #expect(row.asFeedItem.ownerUserID == ownerID)
    }
}
