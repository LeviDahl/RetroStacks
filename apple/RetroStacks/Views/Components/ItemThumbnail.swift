import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Thumbnail / hero art for a catalog or collection item.
///
/// Resolution order: bundled asset (`imageName`) → remote photo (`imageURL`,
/// loaded with `AsyncImage` + the shared `URLCache`) → a tinted SF Symbol
/// placeholder so lists and grids always read well, even offline or mid-load.
struct ItemThumbnail: View {
    var kind: ItemKind
    var platformSymbol: String? = nil
    var imageName: String? = nil
    var imageURL: URL? = nil
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 10
    /// `.fill` crops to the frame (good for small thumbnails); `.fit` shows the
    /// whole object (good for a large detail header on a white-background photo).
    var contentMode: ContentMode = .fill

    private var tint: Color {
        switch kind {
        case .console: .indigo
        case .game: .teal
        case .accessory: .orange
        }
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(imageURL != nil || bundledImage != nil ? AnyShapeStyle(.white) : AnyShapeStyle(.clear))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var content: some View {
        if let bundledImage {
            bundledImage.resizable().aspectRatio(contentMode: contentMode)
        } else if let imageURL {
            AsyncImage(url: imageURL, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .empty:
                    placeholder.overlay {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
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

    private var bundledImage: Image? {
        imageName.flatMap { Image(maybeNamed: $0) }
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
        ItemThumbnail(
            kind: .console,
            imageURL: URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/NES-Console-Set.png?width=800"),
            size: 120, cornerRadius: 16, contentMode: .fit
        )
    }
    .padding()
}
