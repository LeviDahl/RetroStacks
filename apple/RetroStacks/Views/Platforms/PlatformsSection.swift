import SwiftUI
import SwiftData

struct PlatformsSection: View {
    @Query(sort: [SortDescriptor(\Platform.generation), SortDescriptor(\Platform.name)])
    private var platforms: [Platform]

    @State private var selectedID: PersistentIdentifier?
    @State private var searchText = ""

    private var filtered: [Platform] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return platforms }
        return platforms.filter {
            $0.name.lowercased().contains(q)
                || $0.shortName.lowercased().contains(q)
                || $0.manufacturer.lowercased().contains(q)
        }
    }

    #if os(iOS)
    private var grouped: [(era: String, platforms: [Platform])] {
        let dict = Dictionary(grouping: filtered) { $0.eraLabel }
        return dict
            .map { ($0.key, $0.value) }
            .sorted { ($0.platforms.first?.generation ?? 0) < ($1.platforms.first?.generation ?? 0) }
    }
    #endif

    private var selectedPlatform: Platform? {
        guard let selectedID else { return nil }
        return platforms.first { $0.persistentModelID == selectedID }
    }

    var body: some View {
        NavigationSplitView {
            contentColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
        } detail: {
            Group {
                if let selectedPlatform {
                    PlatformDetailView(platform: selectedPlatform)
                } else {
                    EmptyStateView(
                        title: "Pick a Platform",
                        message: "Browse consoles, games, and accessories grouped by system.",
                        systemImage: "gamecontroller"
                    )
                }
            }
            .appNavigationDestinations()
        }
        .navigationTitle("Platforms")
        .searchable(text: $searchText, prompt: "Search platforms")
    }

    @ViewBuilder
    private var contentColumn: some View {
        #if os(macOS)
        ScrollView {
            LazyVGrid(columns: LayoutMetrics.cardColumns(), spacing: LayoutMetrics.cardSpacing) {
                ForEach(filtered) { platform in
                    Button { selectedID = platform.persistentModelID } label: {
                        PlatformCard(platform: platform)
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        if selectedID == platform.persistentModelID {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.tint, lineWidth: 2)
                        }
                    }
                }
            }
            .padding(LayoutMetrics.screenEdgePadding)
        }
        #else
        List(selection: $selectedID) {
            ForEach(grouped, id: \.era) { group in
                Section(group.era) {
                    ForEach(group.platforms) { platform in
                        PlatformRow(platform: platform).tag(platform.persistentModelID)
                    }
                }
            }
        }
        #endif
    }
}

struct PlatformRow: View {
    var platform: Platform
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: platform.iconSystemName)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.name).font(.body.weight(.medium)).lineLimit(1)
                Text("\(platform.manufacturer) · \(yearRange)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(platform.catalogItems.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var yearRange: String {
        let start = platform.releaseYearNA.map(String.init) ?? "?"
        let end = platform.discontinuedYearNA.map(String.init) ?? "—"
        return "\(start)–\(end)"
    }
}

struct PlatformCard: View {
    var platform: Platform

    private var heroImageURL: URL? {
        (platform.consoles.first { $0.imageURL != nil } ?? platform.consoles.first)?.imageURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let heroImageURL {
                    ItemThumbnail(kind: .console, platformSymbol: platform.iconSystemName,
                                  imageURL: heroImageURL, size: 44, cornerRadius: 10, contentMode: .fit)
                } else {
                    Image(systemName: platform.iconSystemName)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                Text(platform.eraLabel)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text(platform.name).font(.headline).lineLimit(2, reservesSpace: true)
            Text(platform.manufacturer).font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                CountPill(count: platform.consoles.count, label: "consoles")
                CountPill(count: platform.games.count, label: "games")
                CountPill(count: platform.accessories.count, label: "acc.")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CountPill: View {
    var count: Int
    var label: String
    var body: some View {
        VStack(spacing: 1) {
            Text("\(count)").font(.callout.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PlatformsSection()
    }
    .modelContainer(SampleData.previewContainer())
}
