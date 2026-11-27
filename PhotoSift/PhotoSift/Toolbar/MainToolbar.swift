import PhotoSiftCore
import SwiftUI

/// The top bar of the window. Identifiers: `toolbar.folderName`, `toolbar.previous`, `toolbar.position`,
/// `toolbar.next`, `toolbar.view.single|grid`, `toolbar.filter.all|darkroom|edited|deletion`, `toolbar.delete`,
/// `toolbar.markDeletion`, `toolbar.darkroom`, `toolbar.edit`, `toolbar.shortcuts`, `toolbar.sendToDarkroom`,
/// `toolbar.export`.
///
/// Decision buttons are icons with tooltips; filters drop their names for icons when the window is narrow.
struct MainToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            title
            if let session = model.session {
                navigation(session)
                viewSwitch(session)
                filters(session)
                Spacer(minLength: 8)
                actions(session)
            } else {
                Spacer()
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(Palette.toolbar)
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.55)).frame(height: 1) }
    }

    // MARK: Parts

    private var title: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.session?.folder.lastPathComponent ?? "Photo Sift")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityIdentifier("toolbar.folderName")
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
        }
        .lineLimit(1)
        .frame(minWidth: 110, maxWidth: 190, alignment: .leading)
    }

    private var subtitle: String {
        guard let session = model.session else { return "Selekcja zdjęć po sesji" }
        return (session.folder.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    private func navigation(_ session: Session) -> some View {
        let noCurrent = session.currentID == nil
        let position = session.currentPosition.map(String.init) ?? "–"
        return HStack(spacing: 0) {
            Button { session.previous() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(GroupButtonStyle())
                .disabled(noCurrent)
                .help("Poprzednie (←)")
                .accessibilityLabel("Poprzednie zdjęcie")
                .accessibilityIdentifier("toolbar.previous")
            Text("\(position) / \(session.visiblePhotos.count)")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 64)
                .accessibilityIdentifier("toolbar.position")
            Button { session.next() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(GroupButtonStyle())
                .disabled(noCurrent)
                .help("Następne — zostaw (→)")
                .accessibilityLabel("Następne zdjęcie")
                .accessibilityIdentifier("toolbar.next")
        }
        .frame(height: 30)
        .background(.white.opacity(0.08), in: Capsule())
        .clipShape(Capsule())
    }

    private func viewSwitch(_ session: Session) -> some View {
        let disabled = session.photos.isEmpty
        return HStack(spacing: 0) {
            Button { if session.viewMode != .single { session.toggleView() } } label: { Image(systemName: "rectangle") }
                .buttonStyle(SegmentButtonStyle(isOn: session.viewMode == .single))
                .help("Pojedyncze zdjęcie (G)")
                .accessibilityLabel("Pojedyncze zdjęcie")
                .accessibilityIdentifier("toolbar.view.single")
            Button { if session.viewMode != .grid { session.toggleView() } } label: { Image(systemName: "square.grid.2x2") }
                .buttonStyle(SegmentButtonStyle(isOn: session.viewMode == .grid))
                .help("Siatka (G)")
                .accessibilityLabel("Siatka")
                .accessibilityIdentifier("toolbar.view.grid")
        }
        .segmentContainer()
        .disabled(disabled)
    }

    private func filters(_ session: Session) -> some View {
        let all = session.photos.count
        let darkroom = session.photos.filter(session.showsDarkroom).count
        let edited = session.photos.filter { session.isEdited($0) }.count
        let deletion = session.deletionCount
        func row(compact: Bool) -> some View {
            HStack(spacing: 0) {
                filterButton("Wszystkie", icon: "photo.on.rectangle", compact: compact, count: all, filter: .all, shortcut: "⌘1", id: "all", session)
                filterButton("Ciemnia", icon: "moon", compact: compact, count: darkroom, filter: .darkroom, shortcut: "⌘2", id: "darkroom", session)
                filterButton("Edytowane", icon: "slider.horizontal.3", compact: compact, count: edited, filter: .edited, shortcut: "⌘3", id: "edited", session)
                filterButton("Do usunięcia", icon: "xmark.bin", compact: compact, count: deletion, filter: .deletion, shortcut: "⌘4", id: "deletion", session)
            }
            .segmentContainer()
            .fixedSize()
        }
        return ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
        .disabled(session.photos.isEmpty)
    }

    private func filterButton(
        _ label: String, icon: String, compact: Bool, count: Int, filter: PhotoFilter, shortcut: String, id: String,
        _ session: Session
    ) -> some View {
        Button { session.setFilter(filter) } label: {
            HStack(spacing: compact ? 4 : 6) {
                if compact { Image(systemName: icon) } else { Text(label) }
                Text("\(count)").foregroundStyle(Palette.secondaryText).monospacedDigit()
            }
        }
        .buttonStyle(SegmentButtonStyle(isOn: session.filter == filter))
        .help("\(label) (\(shortcut))")
        .accessibilityLabel("\(label) \(count)")
        .accessibilityIdentifier("toolbar.filter.\(id)")
    }

    private func actions(_ session: Session) -> some View {
        let noCurrent = session.currentID == nil
        let marked = session.currentPhoto.map(session.isMarked) ?? false
        let markedForDeletion = session.currentPhoto.map(session.isMarkedForDeletion) ?? false
        return HStack(spacing: 6) {
            Button { session.delete() } label: { Image(systemName: "trash") }
                .buttonStyle(PillButtonStyle(kind: .destructive, iconOnly: true))
                .accessibilityLabel("Usuń")
                .disabled(noCurrent)
                .help("Usuń do Kosza (⌫)")
                .accessibilityIdentifier("toolbar.delete")
            Button { session.toggleDeletion() } label: { Image(systemName: "xmark.bin") }
                .buttonStyle(PillButtonStyle(kind: .toggle(isOn: markedForDeletion, tint: Palette.red), iconOnly: true))
                .accessibilityLabel("Do usunięcia")
                .disabled(noCurrent)
                .help("Oznacz do usunięcia przy eksporcie (X)")
                .accessibilityIdentifier("toolbar.markDeletion")
            Button { session.toggleDarkroom() } label: { Image(systemName: "moon") }
                .buttonStyle(PillButtonStyle(kind: .toggle(isOn: marked, tint: Palette.amber), iconOnly: true))
                .accessibilityLabel("Ciemnia")
                .disabled(noCurrent)
                .help("Oznacz jako Ciemnia (C)")
                .accessibilityIdentifier("toolbar.darkroom")
            Button { model.toggleEdit() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(PillButtonStyle(kind: .toggle(isOn: session.mode == .edit, tint: Palette.edited), iconOnly: true))
                .accessibilityLabel("Edycja")
                .disabled(noCurrent)
                .help("Edycja (E — światło i kolor, R — kadr, D — powrót)")
                .accessibilityIdentifier("toolbar.edit")
            Button { model.showShortcuts = true } label: { Image(systemName: "keyboard") }
                .buttonStyle(PillButtonStyle(kind: .icon))
                .help("Skróty klawiszowe (?)")
                .accessibilityLabel("Skróty klawiszowe")
                .accessibilityIdentifier("toolbar.shortcuts")
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 20)
            Button { model.openSheet(.darkroom) } label: {
                Label("Do Ciemni (\(session.darkroomCount))", systemImage: "moon")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(PillButtonStyle())
            .labelStyle(CenteredLabelStyle())
            .disabled(session.darkroomCount == 0)
            .help(model.darkroomTarget == .photos ? "Dodaj oznaczone pliki RAW do Zdjęć" : "Przenieś oznaczone pliki RAW do Ciemnia/")
            .accessibilityIdentifier("toolbar.sendToDarkroom")
            Button { model.openSheet(.export) } label: {
                Label("Eksportuj (\(session.exportCount))", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .labelStyle(CenteredLabelStyle())
            .disabled(!session.canExport)
            .help(session.deletionCount > 0
                ? "Przenieś oznaczone do Kosza (\(session.deletionCount)) i zapisz pozostawione zdjęcia w Album/"
                : "Zapisz pozostawione zdjęcia w Album/")
            .accessibilityIdentifier("toolbar.export")
        }
    }
}

// MARK: Styles

private struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case plain, primary, destructive, icon
        case toggle(isOn: Bool, tint: Color)
    }

    var kind = Kind.plain
    /// A round 32pt button with only an icon (the decision buttons).
    var iconOnly = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, isIcon ? 0 : 12)
            .frame(width: isIcon ? (iconOnly ? 34 : 30) : nil, height: 30)
            .foregroundStyle(foreground)
            .background(background.opacity(pressed ? 0.8 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.38)
            .contentShape(Capsule())
    }

    private var isIcon: Bool {
        if iconOnly { return true }
        if case .icon = kind { return true }
        return false
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case let .toggle(isOn, tint): isOn ? tint : .white.opacity(0.92)
        default: .white.opacity(0.92)
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Palette.primary
        case let .toggle(isOn, tint): isOn ? tint.opacity(0.24) : .white.opacity(0.08)
        default: .white.opacity(0.08)
        }
    }

}

/// Icon and title centred on one axis, so the text sits in the middle of the 30pt pill.
private struct CenteredLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

private struct GroupButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0))
            .opacity(isEnabled ? 1 : 0.38)
            .contentShape(Rectangle())
    }
}

private struct SegmentButtonStyle: ButtonStyle {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .foregroundStyle(isOn ? .white : .white.opacity(0.85))
            .background(.white.opacity(isOn ? 0.22 : 0), in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private extension View {
    func segmentContainer() -> some View {
        padding(2)
            .frame(height: 30)
            .background(.white.opacity(0.08), in: Capsule())
    }
}
