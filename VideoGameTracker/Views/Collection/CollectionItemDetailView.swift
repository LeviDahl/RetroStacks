import SwiftUI
import SwiftData

struct CollectionItemDetailView: View {
    @Bindable var item: CollectionItem

    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                header
                cardGrid
                if !item.notes.isEmpty {
                    DetailCard(title: "Notes", systemImage: "note.text") {
                        Text(item.notes)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let catalogItem = item.catalogItem {
                    DetailCard(title: "Catalog Entry", systemImage: "books.vertical") {
                        NavigationLink(value: catalogItem) {
                            CatalogItemRow(item: catalogItem)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(LayoutMetrics.screenEdgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
            }
            ToolbarItem {
                Menu {
                    statusMenu
                    Divider()
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete from Collection", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { CollectionItemEditView(item: item) }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            ItemThumbnail(
                kind: item.kind,
                platformSymbol: item.catalogItem?.platform?.iconSystemName,
                imageName: item.catalogItem?.imageName,
                size: 120, cornerRadius: 16
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.title2.weight(.bold))
                HStack(spacing: 8) {
                    Text(item.platformShortName)
                    Text("·")
                    Text(item.kind.displayName)
                    if let year = item.catalogItem?.releaseYearNA {
                        Text("·"); Text(String(year))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusBadge(status: item.status)
                    CompletenessBadge(completeness: item.completeness)
                    ConditionLabel(condition: item.condition)
                }

                if let playStatus = item.playStatus, item.kind == .game {
                    Label(playStatus.displayName, systemImage: playStatus.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: Cards

    private var cardGrid: some View {
        let columns: [GridItem] = {
            #if os(macOS)
            [GridItem(.flexible(), spacing: LayoutMetrics.cardSpacing),
             GridItem(.flexible(), spacing: LayoutMetrics.cardSpacing)]
            #else
            [GridItem(.flexible())]
            #endif
        }()

        return LazyVGrid(columns: columns, alignment: .leading, spacing: LayoutMetrics.cardSpacing) {
            valueCard
            completenessCard
            acquisitionCard
            storageCard
        }
    }

    private var valueCard: some View {
        DetailCard(title: "Value", systemImage: "dollarsign.circle") {
            KeyValueRow("Price Paid", Money.string(item.pricePaid))
            KeyValueRow("Estimated Value", Money.string(item.estimatedValue))
            if let delta = item.valueDelta, delta != 0 {
                KeyValueRow("Gain / Loss", Money.signedString(delta),
                            valueColor: delta < 0 ? .red : .green)
            }
            if let catalogItem = item.catalogItem {
                Divider().padding(.vertical, 2)
                Text("Catalog reference (US)")
                    .font(.caption).foregroundStyle(.tertiary)
                KeyValueRow("Loose", Money.string(catalogItem.estimatedValueLoose))
                KeyValueRow("Complete", Money.string(catalogItem.estimatedValueComplete))
                KeyValueRow("Sealed", Money.string(catalogItem.estimatedValueSealed))
            }
        }
    }

    private var completenessCard: some View {
        DetailCard(title: "Condition & Completeness", systemImage: "checklist") {
            KeyValueRow("Condition", item.condition?.displayName ?? "—")
            KeyValueRow("Completeness", item.completeness?.displayName ?? "—")
            if item.gradingCompany != .none {
                KeyValueRow("Grade",
                            "\(item.gradingCompany.displayName) \(item.gradeScore.map { String(format: "%.1f", $0) } ?? "")")
            }
            Divider().padding(.vertical, 2)
            ChecklistRow(label: "Box", isOn: item.hasBox)
            ChecklistRow(label: "Manual", isOn: item.hasManual)
            ChecklistRow(label: "Inserts / Reg card", isOn: item.hasInserts)
            ChecklistRow(label: "Original packaging", isOn: item.hasOriginalPackaging)
        }
    }

    private var acquisitionCard: some View {
        DetailCard(title: "Acquisition", systemImage: "shippingbox") {
            KeyValueRow("Acquired", item.dateAcquired?.mediumDateString ?? "—")
            KeyValueRow("Source", item.acquisitionSource?.displayName ?? "—")
            KeyValueRow("Added to app", item.dateAdded.mediumDateString)
        }
    }

    private var storageCard: some View {
        DetailCard(title: "Storage", systemImage: "archivebox") {
            KeyValueRow("Location", item.storageLocation ?? "—")
            if item.kind == .game {
                KeyValueRow("Play status", item.playStatus?.displayName ?? "—")
            }
        }
    }

    @ViewBuilder
    private var statusMenu: some View {
        Picker("Status", selection: $item.status) {
            ForEach(CollectionStatus.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
        }
        .onChange(of: item.status) { try? modelContext.save() }
    }
}

// MARK: - Reusable detail pieces

struct DetailCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }
}

struct KeyValueRow: View {
    var key: String
    var value: String
    var valueColor: Color = .primary

    init(_ key: String, _ value: String, valueColor: Color = .primary) {
        self.key = key
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

private struct ChecklistRow: View {
    var label: String
    var isOn: Bool
    var body: some View {
        HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? .green : .secondary)
            Text(label)
            Spacer()
        }
        .font(.callout)
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let all = try! container.mainContext.fetch(FetchDescriptor<CollectionItem>())
    let item = all.first { !$0.notes.isEmpty } ?? all[0]
    return NavigationStack {
        CollectionItemDetailView(item: item)
    }
    .modelContainer(container)
}
