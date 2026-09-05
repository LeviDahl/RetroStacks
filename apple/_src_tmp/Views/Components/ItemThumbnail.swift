import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Placeholder box art. Real images get wired in later via `CatalogItem.imageName`;
/// until then this renders a tinted SF Symbol so lists and grids still read well.
struct ItemThumbnail: View {
    var kind: ItemKind
    var platformSymbol: String? = nil
    var imageName: String? = nil
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 10

    private var tint: Color {
        switch kind {
        case .console: .indigo
        case .game: .teal
        case .accessory: .orange
        }
    }

    var body: some View {
        ZStack {
            if let imageName, let uiFriendly = Image(maybeNamed: imageName) {
                uiFriendly
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [tint.opacity(0.85), tint.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: platformSymbol ?? kind.symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private extension Image {
    /// Returns an `Image` only if the asset actually exists in the bundle.
    init?(maybeNamed name: String) {
        #if canImport(UIKit)
        guard UIImage(named: name) != nil else { return nil }
        #elseif canImport(AppKit)
        guard NSImage(named: name) != nil else { return nil }
        #endif
        self.init(name)
    }
}

#Preview("Thumbnails") {
    HStack(spacing: 16) {
        ItemThumbnail(kind: .console, platformSymbol: "gamecontroller")
        ItemThumbnail(kind: .game)
        ItemThumbnail(kind: .accessory, size: 80)
    }
    .padding()
}
