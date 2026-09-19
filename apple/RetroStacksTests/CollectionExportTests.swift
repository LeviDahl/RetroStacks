import Foundation
import SwiftData
import Testing

@testable import RetroStacks

/// Regression for a real, live freeze (2026-09-19): `CollectionSection.body`
/// built the full JSON archive *and* CSV on every render, exporting or not.
/// These lock down that neither is built — or even that the items are
/// touched — unless the exporter is actually presented.
struct CollectionExportTests {
    @MainActor
    private func oneItem() throws -> (container: ModelContainer, items: [CollectionItem]) {
        let url = URL.temporaryDirectory.appending(path: "rs-export-tests-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Platform.self, CatalogItem.self, CollectionItem.self,
            configurations: ModelConfiguration(url: url)
        )
        let item = CollectionItem(status: .owned)
        container.mainContext.insert(item)
        try container.mainContext.save()
        return (container, [item])
    }

    @Test @MainActor func nothingIsBuiltOrTouchedWhileNotPresented() throws {
        let (container, items) = try oneItem()
        defer { withExtendedLifetime(container) {} }
        var touched = 0
        func counted() -> [CollectionItem] { touched += 1; return items }

        let json = CollectionExport.archiveDocument(isPresented: false, items: counted())
        let csv = CollectionExport.csvDocument(isPresented: false, items: counted())

        #expect(touched == 0)
        #expect(json.archive.entries.isEmpty)
        #expect(csv.text.isEmpty)
    }

    @Test @MainActor func archiveIsBuiltOnceWhenPresented() throws {
        let (container, items) = try oneItem()
        defer { withExtendedLifetime(container) {} }
        var touched = 0
        func counted() -> [CollectionItem] { touched += 1; return items }

        let json = CollectionExport.archiveDocument(isPresented: true, items: counted())

        #expect(touched == 1)
        #expect(json.archive.entries.count == 1)
    }

    @Test @MainActor func csvIsBuiltOnceWhenPresented() throws {
        let (container, items) = try oneItem()
        defer { withExtendedLifetime(container) {} }
        var touched = 0
        func counted() -> [CollectionItem] { touched += 1; return items }

        let csv = CollectionExport.csvDocument(isPresented: true, items: counted())

        #expect(touched == 1)
        #expect(!csv.text.isEmpty)
    }
}
