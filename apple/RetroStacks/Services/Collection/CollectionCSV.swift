import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Flat CSV of the collection — the "open it in a spreadsheet / import into
/// another tracker" format, as opposed to `CollectionArchive` (the round-trip
/// backup). One row per live `CollectionItem`; read-only, there's no CSV import.
nonisolated enum CollectionCSV {
    /// Column order is stable — external consumers key off it.
    static let headers = [
        "Title", "Platform", "Kind", "Status", "Condition", "Completeness",
        "Box", "Manual", "Inserts", "Packaging",
        "Grading Company", "Grade",
        "Price Paid", "Estimated Value", "Value Delta",
        "Date Acquired", "Acquired Via", "Storage Location",
        "Play Status", "Date Added", "Notes",
    ]

    @MainActor
    static func string(from items: [CollectionItem]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]

        func money(_ value: Decimal?) -> String {
            guard let value else { return "" }
            return NSDecimalNumber(decimal: value).stringValue
        }
        func date(_ value: Date?) -> String {
            guard let value else { return "" }
            return iso.string(from: value)
        }
        func yn(_ flag: Bool) -> String { flag ? "yes" : "no" }

        var rows: [String] = [row(headers)]
        for item in items.filter({ !$0.isDeleted }).sorted(by: sortKey) {
            rows.append(row([
                item.title,
                item.platformShortName,
                item.kind.displayName,
                item.status.displayName,
                item.condition?.displayName ?? "",
                item.completeness?.displayName ?? "",
                yn(item.hasBox), yn(item.hasManual), yn(item.hasInserts), yn(item.hasOriginalPackaging),
                item.gradingCompany == .none ? "" : item.gradingCompany.displayName,
                item.gradeScore.map { String(format: "%g", $0) } ?? "",
                money(item.pricePaid),
                money(item.estimatedValue),
                money(item.valueDelta),
                date(item.dateAcquired),
                item.acquisitionSource?.displayName ?? "",
                item.storageLocation ?? "",
                item.playStatus?.displayName ?? "",
                date(item.dateAdded),
                item.notes,
            ]))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    @MainActor
    static func data(from items: [CollectionItem]) -> Data {
        Data(string(from: items).utf8)
    }

    // MARK: - Detail

    private static func sortKey(_ a: CollectionItem, _ b: CollectionItem) -> Bool {
        if a.platformShortName != b.platformShortName {
            return a.platformShortName.localizedCaseInsensitiveCompare(b.platformShortName) == .orderedAscending
        }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    /// RFC 4180: quote when the field contains a comma, quote, CR or LF, and
    /// double any embedded quotes.
    private static func row(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return field
        }
        .joined(separator: ",")
    }
}

/// `FileDocument` so `.fileExporter` can write the CSV as a `.csv` file.
nonisolated struct CollectionCSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    static let writableContentTypes: [UTType] = [.commaSeparatedText]

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
