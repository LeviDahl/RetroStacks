import Foundation

/// The one place the JSON archive / CSV export documents get built, and only
/// when an exporter is actually presented. `CollectionSection.body` passes
/// these straight into `.fileExporter(document:)`, which SwiftUI evaluates on
/// *every* body pass — building the full archive (or CSV) of ~1,000 items
/// there was ~2s+ of main-thread work per render, found from a real `sample`
/// of the live app 2026-09-19, whether or not anyone ever exported. `items`
/// is an `@autoclosure` so `CollectionExportTests` can prove that not
/// presented means the items aren't even touched, not just that a cheap
/// result is returned.
enum CollectionExport {
    static func archiveDocument(
        isPresented: Bool, items: @autoclosure () -> [CollectionItem]
    ) -> CollectionDocument {
        guard isPresented else { return CollectionDocument(archive: CollectionArchive(entries: [])) }
        return CollectionDocument(archive: CollectionArchive.make(from: items()))
    }

    static func csvDocument(
        isPresented: Bool, items: @autoclosure () -> [CollectionItem]
    ) -> CollectionCSVDocument {
        guard isPresented else { return CollectionCSVDocument(text: "") }
        return CollectionCSVDocument(text: CollectionCSV.string(from: items()))
    }
}
