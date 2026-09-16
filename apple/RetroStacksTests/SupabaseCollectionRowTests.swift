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

    /// Regression test for the real bug found live 2026-09-16: the first
    /// real `push` of more than one row failed with PostgREST's
    /// `PGRST102: "All object keys must match"`. Root cause was Swift's
    /// synthesized `Encodable` using `encodeIfPresent` for every `Optional`
    /// property — it omits the key entirely when nil rather than writing
    /// `null`, so two rows with different populated optional fields (one has
    /// `price_paid`, another doesn't) produced JSON objects with different
    /// key sets. Fixed with an explicit `encode(to:)`. This test encodes an
    /// *array* of two rows deliberately shaped to differ in which optionals
    /// are nil, then inspects the raw JSON's own keys directly — decoding
    /// back to `SupabaseCollectionRow` wouldn't catch this, since Swift's
    /// decoder tolerates missing keys the way PostgREST's bulk insert
    /// doesn't; the bug only exists in the encoded wire bytes themselves.
    @Test func encodingAnArrayGivesEveryRowTheSameKeySet() throws {
        func row(pricePaid: Decimal?, notes: String) -> SupabaseCollectionRow {
            SupabaseCollectionRow(
                change: CollectionChange(
                    exportID: UUID(), updatedAt: .now, deletedAt: nil,
                    payload: CollectionArchive.Entry(
                        exportID: UUID(), catalogSlug: "nes-smb3", catalogName: nil, platformShortName: nil,
                        status: "owned", condition: "good", completeness: "loose",
                        hasBox: false, hasManual: false, hasInserts: false, hasOriginalPackaging: false,
                        gradingCompany: "none", gradeScore: nil, pricePaid: pricePaid, dateAcquired: nil,
                        acquisitionSource: nil, estimatedValueOverride: nil, storageLocation: nil,
                        notes: notes, playStatus: nil, dateAdded: .now, updatedAt: .now, photosBase64: []
                    )
                ),
                userID: UUID()
            )
        }

        // Deliberately differ in which optionals are populated — this is
        // exactly the shape a real mixed collection produces.
        let rows = [row(pricePaid: 45.00, notes: "has a price"), row(pricePaid: nil, notes: "")]

        let data = try JSONEncoder.exactKeys.encode(rows)
        let jsonArray = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(jsonArray.count == 2)

        let keySets = jsonArray.map { Set($0.keys) }
        #expect(keySets[0] == keySets[1], "PostgREST rejects a bulk insert unless every object has identical keys")
        #expect(keySets[0].contains("price_paid"), "the nil case must still write the key (as null), not omit it")
    }
}
