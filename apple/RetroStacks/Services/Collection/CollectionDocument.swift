import SwiftUI
import UniformTypeIdentifiers

/// `FileDocument` wrapper so `.fileExporter` / `.fileImporter` can move a
/// `CollectionArchive` in and out as a plain `.json` file.
nonisolated struct CollectionDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    static let writableContentTypes: [UTType] = [.json]

    var archive: CollectionArchive

    init(archive: CollectionArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try CollectionArchive.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try archive.encoded())
    }
}
