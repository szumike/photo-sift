import PhotoSiftCore
import SwiftUI

/// The strip of thumbnails under the photo. It always marks exactly one photo (multi-selection is grid-only).
/// A chevron button on its edge hides it; a slim bar with the same button then stays to show it again.
/// Identifiers: `filmstrip`, `filmstrip.thumb.<id>`, `filmstrip.toggle`.
struct Filmstrip: View {
    let session: Session
    let albumStatuses: [String: ExportStatus]
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.filmstripHidden {
            collapsedBar
        } else {
            strip.overlay(alignment: .topTrailing) { toggle.padding(4) }
        }
    }

    private var collapsedBar: some View {
        HStack {
            Spacer()
            toggle
            Spacer()
        }
        .frame(height: 22)
        .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 11))
    }

    private var toggle: some View {
        let hidden = model.filmstripHidden
        return Button { model.filmstripHidden.toggle() } label: {
            Image(systemName: hidden ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.secondaryText)
        .accessibilityLabel(hidden ? "Pokaż pasek miniatur" : "Ukryj pasek miniatur")
        .accessibilityIdentifier("filmstrip.toggle")
        .help(hidden ? "Pokaż pasek miniatur" : "Ukryj pasek miniatur")
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 5) {
                    ForEach(session.visiblePhotos) { item in
                        FilmstripThumb(
                            session: session, item: item,
                            albumStatus: albumStatuses[item.id], isCurrent: item.id == session.currentID
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
            }
            .onAppear { scrollToCurrent(proxy) }
            .onChange(of: session.currentID) { scrollToCurrent(proxy) }
        }
        .frame(height: 72)
        .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmstrip")
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let id = session.currentID else { return }
        proxy.scrollTo(id, anchor: .center)
    }
}

private struct FilmstripThumb: View {
    let session: Session
    let item: PhotoItem
    let albumStatus: ExportStatus?
    let isCurrent: Bool
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    private static let tileHeight: CGFloat = 54

    /// Landscape tiles are 3:2 (as before: 70pt wide); portrait tiles keep the height and narrow to 2:3.
    private var tileWidth: CGFloat {
        let size = session.orientedSize(of: item)
        guard size.height > size.width else { return 70 }
        return (Self.tileHeight * 2 / 3).rounded()
    }

    var body: some View {
        // No modifiers are passed: a ⌘-click or ⇧-click selects one photo like a plain click.
        Button { session.select(item.id) } label: {
            ZStack {
                Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x11 / 255)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileWidth, height: Self.tileHeight)
                        .clipped()
                }
            }
            .frame(width: tileWidth, height: Self.tileHeight)
            .overlay(alignment: .topLeading) {
                StatusBadges(item: item, session: session, albumStatus: albumStatus, showsText: false)
                    .scaleEffect(0.55, anchor: .topLeading)
                    .padding(3)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isCurrent ? Palette.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("filmstrip.thumb.\(item.id)")
        .help(title)
        .task(id: item.id) { image = try? await model.loader.thumbnail(for: item) }
    }

    private var title: String {
        var parts = [item.id]
        if session.isMarkedForDeletion(item) { parts.append("do usunięcia") }
        if session.showsDarkroom(item) { parts.append("Ciemnia") }
        if session.isEdited(item) { parts.append("edytowane") }
        if let albumStatus { parts.append(albumStatus.label) }
        return parts.joined(separator: " · ")
    }
}
