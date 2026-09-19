import SwiftUI
import SwiftData

/// Small modal shown when you `+` a game into the collection — pick the two
/// things you'd otherwise open the editor for (completeness + condition) and
/// you're done. Everything else keeps its default and can be edited later.
///
/// `completeness` is what actually drives pricing (`CatalogItem
/// .referenceValue(for:)` picks the PriceCharting-sourced loose/CIB/sealed
/// tier from it — a real, meaningfully different number per tier, not just
/// a checklist label), so it has to stay in sync with `hasBox`/`hasManual`,
/// not just be a decorative preset next to them. Picking a Completeness
/// preset sets both checkboxes to match it (quick path); toggling a
/// checkbox independently afterward re-derives `completeness` to the
/// closest fit (covers "box but no manual" and "manual but no box" — the
/// latter has no exact `Completeness` case, so it falls back to `.loose`
/// for pricing purposes while `hasManual` itself stays accurate).
struct QuickAddSheet: View {
    var catalogItem: CatalogItem
    var onConfirm: (_ completeness: Completeness, _ condition: ConditionGrade, _ hasBox: Bool, _ hasManual: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var completeness: Completeness = .loose
    @State private var condition: ConditionGrade = .good
    @State private var hasBox = false
    @State private var hasManual = false

    private var hasBoxBinding: Binding<Bool> {
        Binding(
            get: { hasBox },
            set: { newValue in
                hasBox = newValue
                completeness = Self.derivedCompleteness(hasBox: newValue, hasManual: hasManual)
            }
        )
    }

    private var hasManualBinding: Binding<Bool> {
        Binding(
            get: { hasManual },
            set: { newValue in
                hasManual = newValue
                completeness = Self.derivedCompleteness(hasBox: hasBox, hasManual: newValue)
            }
        )
    }

    private static func derivedCompleteness(hasBox: Bool, hasManual: Bool) -> Completeness {
        hasBox && hasManual ? .completeInBox : hasBox ? .boxedNoManual : .loose
    }

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
                .accessibilityHidden(true) // decorative — the title text beside it says the same thing
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalogItem.displayTitle).font(.headline).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(.mutedText).lineLimit(1)
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
            .onChange(of: completeness) { _, newValue in
                switch newValue {
                case .loose: hasBox = false; hasManual = false
                case .boxedNoManual: hasBox = true; hasManual = false
                case .completeInBox, .sealed: hasBox = true; hasManual = true
                case .graded: break // not offered by the picker above
                }
            }

            // Independent of the preset above — picking "CIB" checks both for
            // quick access, but a real collection has edge cases a 4-way
            // preset can't express (box but no manual, or vice versa), so
            // these stay separately toggleable rather than locked to whatever
            // the picker last set.
            HStack(spacing: 20) {
                Toggle("Box", isOn: hasBoxBinding)
                Toggle("Manual", isOn: hasManualBinding)
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif

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
                    onConfirm(completeness, condition, hasBox, hasManual)
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
    // #Preview only, fixture data is always valid.
    // swiftlint:disable:next force_try
    let item = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
        // Fixture data always has a game.
        // swiftlint:disable:next force_unwrapping
        .first { $0.kind == .game }!
    Color.clear
        .sheet(isPresented: .constant(true)) {
            QuickAddSheet(catalogItem: item) { _, _, _, _ in }
        }
        .modelContainer(container)
}
