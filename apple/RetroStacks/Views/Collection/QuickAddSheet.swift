import SwiftUI
import SwiftData

/// Small modal shown when you `+` a game into the collection — pick the two
/// things you'd otherwise open the editor for (completeness + condition) and
/// you're done. Everything else keeps its default and can be edited later.
struct QuickAddSheet: View {
    var catalogItem: CatalogItem
    var onConfirm: (_ completeness: Completeness, _ condition: ConditionGrade) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var completeness: Completeness = .loose
    @State private var condition: ConditionGrade = .good

    private var subtitle: String {
        var parts = [catalogItem.platformShortName]
        if let year = catalogItem.releaseYearNA { parts.append(String(year)) }
        if let pub = catalogItem.manufacturerOrPublisher { parts.append(pub) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ItemThumbnail(
                    kind: catalogItem.kind,
                    platformSymbol: catalogItem.platform?.iconSystemName,
                    imageName: catalogItem.imageName,
                    imageURL: catalogItem.imageURL,
                    size: 52, cornerRadius: 10
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalogItem.displayTitle).font(.headline).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            field("Completeness") {
                Picker("Completeness", selection: $completeness) {
                    Text("Loose").tag(Completeness.loose)
                    Text("Boxed").tag(Completeness.boxedNoManual)
                    Text("CIB").tag(Completeness.completeInBox)
                    Text("Sealed").tag(Completeness.sealed)
                }
            }

            field("Condition") {
                Picker("Condition", selection: $condition) {
                    ForEach([ConditionGrade.mint, .veryGood, .good, .fair, .poor]) {
                        Text($0.displayName).tag($0)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onConfirm(completeness, condition)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        #if os(iOS)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            content()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let item = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
        .first { $0.kind == .game }!
    Color.clear
        .sheet(isPresented: .constant(true)) {
            QuickAddSheet(catalogItem: item) { _, _ in }
        }
        .modelContainer(container)
}
