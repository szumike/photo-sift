import PhotoSiftCore
import SwiftUI

extension Color {
    /// Surface of the cards and the filmstrip.
    static let panelSurface = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x28 / 255)
}

extension ExportStatus {
    /// Polish name of the Album state, as in the prototype.
    var label: String {
        switch self {
        case .current: "Aktualne"
        case .changed: "Zmienione"
        case .notExported: "Nie wyeksportowane"
        case .skipped(.deletion): "Do usunięcia przy eksporcie"
        case .skipped: "Pomijane"
        case .conflict: "Inny plik o tej nazwie"
        }
    }
}

/// The side panel: file, metadata and the "Stan" section; in edit mode `EditPanel` replaces "Stan".
/// Identifiers: `info.fileName`, `info.type`, `info.camera`, `info.lens`, `info.iso`, `info.aperture`,
/// `info.exposureTime`, `info.focalLength`, `info.date`, `info.state.deletion|darkroom|edit|album`, `info.rawOnlyNote`.
struct InfoPanel: View {
    let session: Session
    let albumStatus: ExportStatus?

    private struct LoadedMetadata {
        let id: String
        let value: PhotoMetadata
    }

    @State private var loaded: LoadedMetadata?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                // The last card takes the height left over, down to the bottom of the window.
                VStack(spacing: 8) {
                    if let item = session.currentPhoto {
                        card { details(item) }
                        if session.mode == .edit {
                            EditPanel(session: session)
                                .frame(maxHeight: .infinity)
                        } else {
                            card(fillsHeight: true) { stateSection(item) }
                        }
                    } else {
                        card(fillsHeight: true) {
                            Text("Brak wybranego zdjęcia.")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                }
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .frame(minHeight: geometry.size.height)
            }
        }
        .task(id: session.currentID) {
            guard let item = session.currentPhoto else { return }
            loaded = LoadedMetadata(id: item.id, value: await Self.readMetadata(of: item))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("info")
    }

    @concurrent nonisolated private static func readMetadata(of item: PhotoItem) async -> PhotoMetadata {
        guard let url = item.jpegURL ?? item.rawURL else { return PhotoMetadata() }
        return PhotoMetadata.read(from: url)
    }

    // MARK: Sections

    private func details(_ item: PhotoItem) -> some View {
        let metadata = loaded?.id == item.id ? loaded?.value : nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.id)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityIdentifier("info.fileName")
                Spacer(minLength: 8)
                Text(typeText(item))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondaryText)
                    .accessibilityIdentifier("info.type")
            }
            VStack(alignment: .leading, spacing: 12) {
                line("camera", metadata?.camera, help: "Aparat", id: "info.camera")
                line("camera.aperture", metadata?.lens, help: "Obiektyw", id: "info.lens")
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        cell("circle.lefthalf.filled", metadata?.formattedISO, help: "Czułość ISO", id: "info.iso")
                        cell("f.cursive", metadata?.formattedAperture, help: "Przysłona", id: "info.aperture")
                    }
                    GridRow {
                        cell("timer", metadata?.formattedExposureTime, help: "Czas naświetlania", id: "info.exposureTime")
                        cell("arrow.left.and.right", metadata?.formattedFocalLength, help: "Ogniskowa", id: "info.focalLength")
                    }
                }
                line("calendar", metadata?.formattedDate, help: "Data wykonania", id: "info.date")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stateSection(_ item: PhotoItem) -> some View {
        let marked = session.isMarked(item) || session.isSent(item)
        let edit = editText(item)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Stan")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
            if session.isMarkedForDeletion(item) {
                stateRow("xmark.bin.fill", "Usuwanie", "Przy eksporcie", color: Palette.red, id: "info.state.deletion")
            }
            stateRow(
                "moon.fill", "Ciemnia",
                marked ? (session.isSent(item) ? (session.isInPhotos(item) ? "RAW w Zdjęciach" : "RAW w Ciemnia/") : "Oznaczone") : "Nie",
                color: marked ? Palette.amber : Palette.secondaryText, id: "info.state.darkroom"
            )
            stateRow(
                "slider.horizontal.3", "Edycja", edit ?? "Brak",
                color: edit == nil ? Palette.secondaryText : Palette.edited, id: "info.state.edit"
            )
            stateRow(
                "folder", "Album/", albumStatus?.label ?? "–",
                color: albumColor, id: "info.state.album"
            )
            if item.isRawOnly {
                Text("Brak JPEG-a. Podgląd z miniatury w ARW. Edycja i eksport niedostępne.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 4)
                    .accessibilityIdentifier("info.rawOnlyNote")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func card<Content: View>(fillsHeight: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: fillsHeight ? .topLeading : .leading)
            .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func line(_ icon: String, _ text: String?, help: String, id: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 18)
            Text(text ?? "—")
                .font(.system(size: 13))
                .accessibilityIdentifier(id)
        }
        .help(help)
    }

    private func cell(_ icon: String, _ text: String?, help: String, id: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
            Text(text ?? "—")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .accessibilityIdentifier(id)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .help(help)
    }

    private func stateRow(_ icon: String, _ key: String, _ value: String, color: Color, id: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(key)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(color == Palette.secondaryText ? .white.opacity(0.9) : color)
                .accessibilityIdentifier(id)
        }
        .font(.system(size: 13))
    }

    private var albumColor: Color {
        switch albumStatus {
        case .current: Palette.green
        case .changed: Palette.yellow
        case .notExported: .white.opacity(0.9)
        default: Palette.secondaryText
        }
    }

    private func typeText(_ item: PhotoItem) -> String {
        if item.isRawOnly { return "tylko ARW" }
        return item.rawURL == nil ? "tylko JPG" : "JPG + ARW"
    }

    /// "kadr, prost., BB" for the edits the photo has; nil without an edit.
    private func editText(_ item: PhotoItem) -> String? {
        guard let edit = session.state(of: item.id).edit else { return nil }
        var parts: [String] = []
        if edit.crop.width < 0.999 || edit.crop.height < 0.999 { parts.append("kadr") }
        if abs(edit.angle) > 0.05 { parts.append("prost.") }
        if edit.temperature != 0 || edit.tint != 0 { parts.append("BB") }
        if edit.exposure != 0 { parts.append("ekspozycja") }
        if edit.highlights != 0 || edit.shadows != 0 { parts.append("światła/cienie") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
