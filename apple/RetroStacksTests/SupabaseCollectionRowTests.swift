import Foundation
import Testing

@testable import RetroStacks

/// Regression coverage for the bug found 2026-09-13 alongside the
/// `AccountService`/`SupabaseSessionStore` one: `SupabaseCollectionRow` used
/// `JSONDecoder.supabase` (`.convertFromSnakeCase`), which mis-decodes
/// `"user_id"` back to `"userId"` (lowercase d) instead of `"userID"` —
/// a `keyNotFound` on every single row, since `user_id` is a `NOT NULL`
/// column present on every row `pull()` could ever return. This test decodes
/// a realistic PostgREST response shape directly, the same way `pull()` does,
/// rather than going through a fake engine that bypasses the wire format
/// entirely (as `SyncCoordinatorTests` deliberately does for the merge logic).
struct SupabaseCollectionRowTests {
    private static let realisticRow = """
    [
      {
        "id": "8C9E2B0A-6A5E-4B8A-9C1E-1B2C3D4E5F60",
        "user_id": "1A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9",
        "catalog_slug": "snes-chrono-trigger",
        "status": "owned",
        "condition": "very_good",
        "completeness": "complete_in_box",
        "has_box": true,
        "has_manual": true,
        "has_inserts": false,
        "has_original_packaging": true,
        "grading_company": "none",
        "grade_score": null,
        "price_paid": 45.00,
        "date_acquired": "2024-03-01T00:00:00Z",
        "acquisition_source": "online_marketplace",
        "estimated_value_override": null,
        "storage_location": "Shelf B",
        "notes": "",
        "play_status": "completed",
        "date_added": "2024-03-01T00:00:00Z",
        "updated_at": "2024-03-02T00:00:00Z",
        "deleted_at": null
      }
    ]
    """

    @Test func decodesARealisticPostgRESTRow() throws {
        let data = try #require(Self.realisticRow.data(using: .utf8))
        let rows = try JSONDecoder.exactKeys.decode([SupabaseCollectionRow].self, from: data)
        let row = try #require(rows.first)

        #expect(row.userID.uuidString == "1A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9")
        #expect(row.catalogSlug == "snes-chrono-trigger")
        #expect(row.hasBox == true)
        #expect(row.hasInserts == false)
        #expect(row.notes == "")

        // The actual regression: this used to throw before landing on the
        // change, not just produce a wrong value — confirm the whole mapping
        // survives, not just the field that happened to break.
        let change = row.asChange
        #expect(change.exportID == row.id)
        #expect(change.payload?.catalogSlug == "snes-chrono-trigger")
    }

    @Test func roundTripsThroughEncodeAndDecode() throws {
        let original = SupabaseCollectionRow(
            change: CollectionChange(
                exportID: UUID(), updatedAt: .now, deletedAt: nil,
                payload: CollectionArchive.Entry(
                    exportID: UUID(), catalogSlug: "genesis-sonic-2", catalogName: nil, platformShortName: nil,
                    status: "owned", condition: "good", completeness: "loose",
                    hasBox: false, hasManual: false, hasInserts: false, hasOriginalPackaging: false,
                    gradingCompany: "none", gradeScore: nil, pricePaid: nil, dateAcquired: nil,
                    acquisitionSource: nil, estimatedValueOverride: nil, storageLocation: nil,
                    notes: "test", playStatus: nil, dateAdded: .now, updatedAt: .now, photosBase64: []
                )
            ),
            userID: UUID()
        )

        let data = try JSONEncoder.exactKeys.encode(original)
        let decoded = try JSONDecoder.exactKeys.decode(SupabaseCollectionRow.self, from: data)
        #expect(decoded.userID == original.userID)
        #expect(decoded.id == original.id)
        #expect(decoded.catalogSlug == original.catalogSlug)
    }
}
