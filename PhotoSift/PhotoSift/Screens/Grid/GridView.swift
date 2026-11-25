import PhotoSiftCore
import SwiftUI

/// The grid: thumbnails of the visible photos with the selection, and the side panel.
/// Identifiers: `screen.grid`, `grid.info`, `grid.empty`, `grid.selectionCount`, `grid.clearSelection`; the parts add their own.
struct GridView: View {
    let session: Session
    @Environment(AppModel.self) private var model

    private static let minCellWidth: CGFloat = 150
    private static let spacing: CGFloat = 10
    private static let padding: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                photosGrid
            }
            .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(8)
            VStack(spacing: 0) {
                if session.selection.count > 1 {
                    GridSelectionPanel(session: session)
                }
                InfoPanel(session: session, albumStatus: session.currentID.flatMap { session.exportStatuses[$0] })
            }
            .frame(width: 300)
        }
        .background { Color.clear.accessibilityIdentifier("screen.grid") }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(infoText)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.secondaryText)
                .accessibilityIdentifier("grid.info")
            Spacer()
            if session.selection.count > 1 {
                HStack(spacing: 4) {
                    Text("\(session.selection.count) \(PolishPlural.form(session.selection.count, one: "zaznaczone", few: "zaznaczone", many: "zaznaczonych"))")
                        .accessibilityIdentifier("grid.selectionCount")
                    Button { session.clearSelection() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .heavy))
                            .frame(width: 18, height: 18)
                            .background(Color(red: 140 / 255, green: 196 / 255, blue: 1, opacity: 0.22), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Odznacz (esc)")
                    .accessibilityLabel("Odznacz")
                    .accessibilityIdentifier("grid.clearSelection")
                }
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(red: 140 / 255, green: 196 / 255, blue: 1))
                .padding(.leading, 10)
                .padding(.trailing, 3)
                .frame(height: 24)
                .background(Palette.accent.opacity(0.22), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var infoText: String {
        let count = session.visiblePhotos.count
        var text = PolishPlural.photos(count)
        switch session.filter {
        case .all: break
        case .darkroom: text += " · filtr: Ciemnia"
        case .edited: text += " · filtr: Edytowane"
        }
        return text
    }

    // MARK: Photos

    private var photosGrid: some View {
        GeometryReader { geometry in
            let columns = Self.columnCount(for: geometry.size.width)
            ScrollViewReader { proxy in
                ScrollView {
                    let visible = session.visiblePhotos
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns),
                        spacing: Self.spacing
                    ) {
                        ForEach(visible) { item in
                            GridCell(
                                session: session, item: item, albumStatus: session.exportStatuses[item.id],
                                isSelected: session.selection.contains(item.id),
                                showsCheck: session.selection.count > 1
                            )
                            .id(item.id)
                        }
                    }
                    .padding(Self.padding)
                    if visible.isEmpty && !session.photos.isEmpty {
                        Text(session.filter == .darkroom ? "Brak zdjęć w Ciemni" : "Brak edytowanych zdjęć")
                            .foregroundStyle(Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.66))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .accessibilityIdentifier("grid.empty")
                    }
                }
                .onAppear {
                    model.viewState.gridColumns = columns
                    scrollToCurrent(proxy, animated: false)
                }
                .onChange(of: columns) { model.viewState.gridColumns = columns }
                .onChange(of: session.currentID) { scrollToCurrent(proxy, animated: true) }
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = session.currentID else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private static func columnCount(for width: CGFloat) -> Int {
        max(1, Int((width - 2 * padding + spacing) / (minCellWidth + spacing)))
    }
}
