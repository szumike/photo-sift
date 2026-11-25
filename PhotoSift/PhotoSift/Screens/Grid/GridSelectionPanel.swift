import PhotoSiftCore
import SwiftUI

/// The side-panel box for a multi-selection: its size, "Wklej balans bieli" and "Odznacz".
/// Identifiers: `grid.selection`, `grid.selection.title`, `grid.selection.paste`, `grid.selection.clear`.
struct GridSelectionPanel: View {
    let session: Session

    var body: some View {
        let count = session.selection.count
        VStack(alignment: .leading, spacing: 8) {
            Text("Zaznaczono \(PolishPlural.photos(count))")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityIdentifier("grid.selection.title")
            HStack(spacing: 6) {
                Button("Wklej balans bieli") { session.pasteWhiteBalance() }
                    .disabled(session.whiteBalanceClipboard == nil)
                    .help("⇧⌘V")
                    .accessibilityIdentifier("grid.selection.paste")
                Button("Odznacz") { session.clearSelection() }
                    .help("esc")
                    .accessibilityIdentifier("grid.selection.clear")
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.trailing, 8)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grid.selection")
    }
}
