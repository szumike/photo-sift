import AppKit
import PhotoSiftCore
import SwiftUI

/// One thumbnail of the grid: image, file name, badges and the selection check.
/// Click selects (⌘ toggles, ⇧ extends a range), double-click opens the photo.
/// Identifier: `grid.cell.<id>`.
struct GridCell: View {
    let session: Session
    let item: PhotoItem
    let albumStatus: ExportStatus?
    let isSelected: Bool
    let showsCheck: Bool
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            Text(item.id)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.7))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .background(Color(red: 0x1b / 255, green: 0x1b / 255, blue: 0x1d / 255), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topLeading) {
            StatusBadges(item: item, session: session, albumStatus: albumStatus, showsText: false)
                .scaleEffect(0.8, anchor: .topLeading)
                .padding(6)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected && showsCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Palette.accent, in: Circle())
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent, lineWidth: isSelected ? 2 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
            var modifiers: SelectionModifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            session.select(item.id, modifiers: modifiers)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { session.openInSingle(item.id) })
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("grid.cell.\(item.id)")
        .task(id: item.id) { image = try? await model.loader.thumbnail(for: item) }
    }

    private var title: String {
        var parts = [item.id]
        if session.isMarked(item) || item.isSentToDarkroom { parts.append("Ciemnia") }
        if session.isEdited(item) { parts.append("edytowane") }
        if let albumStatus { parts.append(albumStatus.label) }
        return parts.joined(separator: " · ")
    }
}
