import PhotosUI
import SwiftUI
import SwiftData

/// Form for a single `CollectionItem`. Edits the model directly; Cancel rolls
/// back via the context, Save commits.
struct CollectionItemEditView: View {
    @Bindable var item: CollectionItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var photoPicks: [PhotosPickerItem] = []
    @State private var importingPhotos = false

    var body: some View {
        Form {
            Section("Status") {
                Picker("Status", selection: $item.status) {
                    ForEach(CollectionStatus.allCases) {
                        Label($0.displayName, systemImage: $0.symbol).tag($0)
                    }
                }
                if item.kind == .game {
                    Picker("Play Status", selection: Binding(
                        get: { item.playStatus ?? .notStarted },
                        set: { item.playStatus = $0 }
                    )) {
                        ForEach(PlayStatus.allCases) { Text($0.displayName).tag($0) }
                    }
                }
            }

            Section("Condition & Completeness") {
                Picker("Condition", selection: Binding(
                    get: { item.condition ?? .good },
                    set: { item.condition = $0 }
                )) {
                    ForEach(ConditionGrade.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Completeness", selection: Binding(
                    get: { item.completeness ?? .loose },
                    set: { item.completeness = $0 }
                )) {
                    ForEach(Completeness.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Box", isOn: $item.hasBox)
                Toggle("Manual", isOn: $item.hasManual)
                Toggle("Inserts / Registration card", isOn: $item.hasInserts)
                Toggle("Original packaging", isOn: $item.hasOriginalPackaging)
            }

            Section("Grading") {
                Picker("Grading Company", selection: $item.gradingCompany) {
                    ForEach(GradingCompany.allCases) { Text($0.displayName).tag($0) }
                }
                if item.gradingCompany != .none {
                    LabeledContent("Grade Score") {
                        TextField("e.g. 9.4", value: Binding(
                            get: { item.gradeScore ?? 0 },
                            set: { item.gradeScore = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    }
                }
            }

            Section("Value") {
                LabeledContent("Price Paid") {
                    TextField("Price Paid", value: $item.pricePaid.orZero,
                              format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                }
                LabeledContent("Estimated Value Override") {
                    TextField("Auto from catalog", value: $item.estimatedValueOverride.orZero,
                              format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                }
                if let ref = item.catalogItem?.referenceValue(for: item.completeness) {
                    Text("Catalog reference: \(Money.string(ref))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Acquisition") {
                Toggle("Has acquisition date", isOn: $item.dateAcquired.presence)
                if item.dateAcquired != nil {
                    DatePicker("Date Acquired", selection: $item.dateAcquired.orNow,
                               displayedComponents: .date)
                }
                Picker("Source", selection: Binding(
                    get: { item.acquisitionSource ?? .other },
                    set: { item.acquisitionSource = $0 }
                )) {
                    ForEach(AcquisitionSource.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section("Storage & Notes") {
                TextField("Storage Location", text: $item.storageLocation.orEmpty)
                TextField("Notes", text: $item.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            photosSection
        }
        .formStyle(.grouped)
        .navigationTitle("Edit Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    modelContext.rollback()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if modelContext.hasChanges { item.touch() }
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    // MARK: - Photos

    private var photosSection: some View {
        Section {
            if !item.photoData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(item.photoData.enumerated()), id: \.offset) { index, data in
                            photoThumbnail(data, at: index)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            PhotosPicker(
                selection: $photoPicks,
                maxSelectionCount: max(1, PhotoImport.maxPhotosPerItem - item.photoData.count),
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    item.photoData.isEmpty ? "Add Photos" : "Add More Photos",
                    systemImage: "photo.badge.plus"
                )
            }
            .disabled(importingPhotos || item.photoData.count >= PhotoImport.maxPhotosPerItem)

            if importingPhotos {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Adding photos…").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Stored with your collection and included in exports. Up to \(PhotoImport.maxPhotosPerItem).")
        }
        .onChange(of: photoPicks) { _, picks in
            guard !picks.isEmpty else { return }
            loadPhotos(picks)
        }
    }

    private func photoThumbnail(_ data: Data, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = Image(photoData: data) {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                item.photoData.remove(at: index)
                item.touch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.body)
            }
            .buttonStyle(.plain)
            .padding(3)
        }
    }

    private func loadPhotos(_ picks: [PhotosPickerItem]) {
        importingPhotos = true
        Task {
            var added: [Data] = []
            for pick in picks {
                if let raw = try? await pick.loadTransferable(type: Data.self),
                   let jpeg = PhotoImport.normalizedJPEG(from: raw) {
                    added.append(jpeg)
                }
            }
            let room = PhotoImport.maxPhotosPerItem - item.photoData.count
            if room > 0 { item.photoData.append(contentsOf: added.prefix(room)) }
            if !added.isEmpty { item.touch() }
            photoPicks = []
            importingPhotos = false
        }
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let item = try! container.mainContext.fetch(FetchDescriptor<CollectionItem>()).first!
    NavigationStack {
        CollectionItemEditView(item: item)
    }
    .modelContainer(container)
}
