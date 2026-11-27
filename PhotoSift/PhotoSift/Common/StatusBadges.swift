import PhotoSiftCore
import SwiftUI

/// Colors of the prototype shared by all screens.
enum Palette {
    static let window = Color(red: 0x1e / 255, green: 0x1e / 255, blue: 0x20 / 255)
    static let toolbar = Color(red: 0x2a / 255, green: 0x2a / 255, blue: 0x2c / 255)
    static let stage = Color(red: 0x2b / 255, green: 0x2b / 255, blue: 0x2b / 255)
    static let secondaryText = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.62)
    static let primary = Color(red: 0x0b / 255, green: 0x67 / 255, blue: 0xd6 / 255)
    static let accent = Color(red: 0x0a / 255, green: 0x84 / 255, blue: 1)
    static let amber = Color(red: 1, green: 0xb3 / 255, blue: 0x40 / 255)
    static let edited = Color(red: 0x79 / 255, green: 0xb8 / 255, blue: 1)
    static let green = Color(red: 0x30 / 255, green: 0xd1 / 255, blue: 0x58 / 255)
    static let yellow = Color(red: 1, green: 0xd6 / 255, blue: 0x0a / 255)
    static let red = Color(red: 1, green: 0x45 / 255, blue: 0x3a / 255)
}

/// The badges of one photo: RAW only, Darkroom, edit lock, edited, Album state.
/// Used by the preview, the filmstrip and the grid. Identifiers: `badge.rawOnly`, `badge.darkroom`,
/// `badge.deletion`, `badge.locked`, `badge.edited`, `badge.album.current|changed|new`.
struct StatusBadges: View {
    let item: PhotoItem
    let session: Session
    /// Album state of the photo, e.g. from `Session.exportPlan()`; nil or a skipped/conflict status shows no badge.
    var albumStatus: ExportStatus?
    /// Show the "Edycja zablokowana" badge (the single view while editing).
    var showsLock = false
    /// Text next to the icons (preview) or icons only (thumbnails).
    var showsText = true

    var body: some View {
        HStack(spacing: 6) {
            if item.isRawOnly {
                badge("Tylko RAW", icon: "photo", color: Color(white: 0.9), id: "badge.rawOnly", help: "Tylko RAW · podgląd z miniatury w ARW")
            }
            if session.showsDarkroom(item) {
                badge(
                    session.isInPhotos(item) ? "Ciemnia · RAW w Zdjęciach" : session.isSent(item) ? "Ciemnia · RAW przeniesiony" : "Ciemnia",
                    icon: "moon.fill", color: Palette.amber, id: "badge.darkroom", help: "Ciemnia"
                )
            }
            if session.isMarkedForDeletion(item) {
                badge("Do usunięcia", icon: "xmark.bin.fill", color: Palette.red, id: "badge.deletion", help: "Do usunięcia przy eksporcie")
            }
            if showsLock && session.isEditLocked(item) {
                badge("Edycja zablokowana", icon: "lock.fill", color: Palette.amber, id: "badge.locked", help: "Edycja zablokowana")
            }
            if session.isEdited(item) {
                badge(nil, icon: "slider.horizontal.3", color: Palette.edited, id: "badge.edited", help: "Edytowane")
            }
            switch albumStatus {
            case .current:
                badge(nil, icon: "checkmark.circle.fill", color: Palette.green, id: "badge.album.current", help: "W Albumie, aktualne")
            case .changed:
                badge(nil, icon: "arrow.triangle.2.circlepath", color: Palette.yellow, id: "badge.album.changed", help: "Zmienione od eksportu")
            case .notExported:
                badge(nil, icon: "circle.dashed", color: .white.opacity(0.85), id: "badge.album.new", help: "Nie wyeksportowane")
            default:
                EmptyView()
            }
        }
    }

    private func badge(_ text: String?, icon: String, color: Color, id: String, help: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            if showsText, let text { Text(text).font(.system(size: 12, weight: .semibold)) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, showsText && text != nil ? 10 : 6)
        .frame(height: 26)
        .background(Color(red: 24 / 255, green: 24 / 255, blue: 26 / 255, opacity: 0.86), in: Capsule())
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
    }
}
