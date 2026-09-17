import SwiftUI
import SwiftData

/// Sheet for creating a private catalog entry: either a new variant of an
/// existing item (5-screw NES, black label, …) or a wholly new entry the
/// shared catalog is missing. One form covers both — `variantOf` just
/// prefills name/platform/kind and locks the platform, since a variant has to
/// stay on the same platform as the item it varies; everything else, and the
/// whole form for a from-scratch entry, is freely editable.
struct CustomCatalogItemSheet: View {
    var variantOf: CatalogItem?
    var initialPlatformSlug: String?
    var initialName: String = ""
    /// Fires after a successful save, right after this sheet dismisses
    /// itself — lets a caller like `AddToCollectionFlow` continue straight
    /// into its own `add(_:)` (the same `QuickAddSheet`-or-direct-add path
    /// every other catalog item there goes through), so creating a custom
    /// entry from "Add to Collection" actually adds it, not just creates it.
    var onCreated: (CatalogItem) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Platform.generation) private var platforms: [Platform]

    @State private var name: String
    @State private var variant = ""
    @State private var kind: ItemKind
    @State private var platformSlug: String?
    @State private var releaseYear = ""
    @State private var manufacturerOrPublisher = ""
    @State private var developer = ""
    @State private var genre = ""
    @State private var upc = ""
    @State private var summary = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        variantOf: CatalogItem? = nil,
        initialPlatformSlug: String? = nil,
        initialName: String = "",
        onCreated: @escaping (CatalogItem) -> Void = { _ in }
    ) {
        self.variantOf = variantOf
        self.initialPlatformSlug = initialPlatformSlug
        self.initialName = initialName
        self.onCreated = onCreated
        _name = State(initialValue: variantOf?.name ?? initialName)
        _kind = State(initialValue: variantOf?.kind ?? .game)
        _platformSlug = State(initialValue: variantOf?.platform?.slug ?? initialPlatformSlug)
        _manufacturerOrPublisher = State(initialValue: variantOf?.manufacturerOrPublisher ?? "")
        _developer = State(initialValue: variantOf?.developer ?? "")
        _genre = State(initialValue: variantOf?.genre ?? "")
        _releaseYear = State(initialValue: variantOf?.releaseYearNA.map(String.init) ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && platformSlug != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField(
                        variantOf == nil ? "Variant (optional)" : "Variant — e.g. 5-Screw, Black Label",
                        text: $variant
                    )
                    Picker("Kind", selection: $kind) {
                        ForEach(ItemKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    .disabled(variantOf != nil)
                    Picker("Platform", selection: $platformSlug) {
                        Text("Choose a Platform").tag(String?.none)
                        ForEach(platforms) { Text($0.shortName).tag(String?.some($0.slug)) }
                    }
                    .disabled(variantOf != nil)
                }
                Section("Details") {
                    TextField("Release Year (US)", text: $releaseYear)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField(kind == .game ? "Publisher" : "Manufacturer", text: $manufacturerOrPublisher)
                    if kind == .game {
                        TextField("Developer", text: $developer)
                        TextField("Genre", text: $genre)
                    }
                    TextField("UPC", text: $upc)
                }
                Section("Summary") {
                    TextField("Notes about this entry", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(variantOf == nil ? "Add Custom Entry" : "Add a Variant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!isValid)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private func save() {
        guard let platformSlug else { return }
        let platform = platforms.first { $0.slug == platformSlug }
        let trimmedVariant = variant.trimmingCharacters(in: .whitespaces)
        let draft = CustomCatalogItemService.Draft(
            platformSlug: platformSlug,
            kind: kind,
            name: name.trimmingCharacters(in: .whitespaces),
            variant: trimmedVariant.isEmpty ? nil : trimmedVariant,
            releaseYearNA: Int(releaseYear),
            manufacturerOrPublisher: manufacturerOrPublisher.isEmpty ? nil : manufacturerOrPublisher,
            developer: developer.isEmpty ? nil : developer,
            genre: genre.isEmpty ? nil : genre,
            upc: upc.isEmpty ? nil : upc,
            summary: summary.isEmpty ? nil : summary
        )
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let item = try await CustomCatalogItemActions.create(draft, platform: platform, in: modelContext)
                isSaving = false
                dismiss()
                onCreated(item)
            } catch SyncError.notSignedIn {
                isSaving = false
                errorMessage = "Sign in to add a custom catalog entry — it's saved to your account, not just this device."
            } catch {
                isSaving = false
                errorMessage = (error as? CatalogError)?.userMessage ?? "Couldn't save: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    let container = SampleData.previewContainer()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CustomCatalogItemSheet()
        }
        .modelContainer(container)
}

#Preview("Add a Variant") {
    let container = SampleData.previewContainer()
    // #Preview only, fixture data is always valid.
    // swiftlint:disable:next force_try
    let all = try! container.mainContext.fetch(FetchDescriptor<CatalogItem>())
    let item = all.first { $0.slug == "snes-chrono-trigger" } ?? all[0]
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CustomCatalogItemSheet(variantOf: item)
        }
        .modelContainer(container)
}
