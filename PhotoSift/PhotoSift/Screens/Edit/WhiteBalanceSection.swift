import PhotoSiftCore
import SwiftUI

/// "Światło i kolor": the exposure, highlights and shadows sliders and "Balans bieli" (temperature and tint sliders with copy and paste buttons).
/// Identifiers: `edit.copyWB`, `edit.pasteWB`, `edit.temperature`, `edit.temperature.value`,
/// `edit.tint`, `edit.tint.value`, `edit.exposure`, `edit.exposure.value`,
/// `edit.highlights`, `edit.highlights.value`, `edit.shadows`, `edit.shadows.value`.
struct WhiteBalanceSection: View {
    let session: Session

    /// Ukryte na życzenie użytkownika, kod zostaje na przyszłość.
    static let showsHighlightsShadows = false

    var body: some View {
        let params = session.currentEditParams
        VStack(alignment: .leading, spacing: 10) {
            EditSectionLabel("Światło")
            EditSlider(
                title: "Ekspozycja", id: "edit.exposure",
                value: binding(params?.exposure ?? 0) { $0.exposure = $1 },
                range: -2...2, step: 0.05, neutral: 0, track: .exposure, format: Self.formatEV,
                onEditingChanged: gesture, keyStep: 0.1
            )
            .padding(.bottom, Self.showsHighlightsShadows ? 0 : 8)
            if Self.showsHighlightsShadows {
                EditSlider(
                    title: "Światła", id: "edit.highlights",
                    value: binding(params?.highlights ?? 0) { $0.highlights = $1 },
                    range: -100...100, step: 1, neutral: 0, track: .plain, format: Self.format,
                    onEditingChanged: gesture, keyStep: 5
                )
                EditSlider(
                    title: "Cienie", id: "edit.shadows",
                    value: binding(params?.shadows ?? 0) { $0.shadows = $1 },
                    range: -100...100, step: 1, neutral: 0, track: .plain, format: Self.format,
                    onEditingChanged: gesture, keyStep: 5
                )
                .padding(.bottom, 8)
            }
            HStack {
                EditSectionLabel("Balans bieli")
                Spacer()
                HStack(spacing: 4) {
                    iconButton("doc.on.doc", help: "Kopiuj balans bieli (⇧⌘C)", id: "edit.copyWB") {
                        session.copyWhiteBalance()
                    }
                    iconButton(
                        "doc.on.clipboard",
                        help: pasteHelp,
                        id: "edit.pasteWB",
                        disabled: session.whiteBalanceClipboard == nil
                    ) {
                        session.pasteWhiteBalance()
                    }
                }
            }
            EditSlider(
                title: "Temperatura", id: "edit.temperature",
                value: binding(params?.temperature ?? 0) { $0.temperature = $1 },
                range: -100...100, step: 1, neutral: 0, track: .temperature, format: Self.format,
                onEditingChanged: gesture, keyStep: 5
            )
            EditSlider(
                title: "Tint", id: "edit.tint",
                value: binding(params?.tint ?? 0) { $0.tint = $1 },
                range: -100...100, step: 1, neutral: 0, track: .tint, format: Self.format,
                onEditingChanged: gesture, keyStep: 5
            )
        }
        .padding(.top, 16)
    }

    private var pasteHelp: String {
        session.targetIDs.count > 1
            ? "Wklej balans bieli na \(session.targetIDs.count) zaznaczone (⇧⌘V)"
            : "Wklej balans bieli (⇧⌘V)"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%+.0f", value + 0).replacingOccurrences(of: "+0", with: "0")
    }

    /// "+0,5 EV" with the Polish decimal comma; zero reads "0 EV".
    private static func formatEV(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        guard rounded != 0 else { return "0 EV" }
        return String(format: "%+.1f EV", rounded).replacingOccurrences(of: ".", with: ",")
    }

    private func gesture(_ isEditing: Bool) {
        if isEditing { session.beginEditGesture() } else { session.endEditGesture() }
    }

    private func binding(_ current: Double, apply: @escaping (inout EditParams, Double) -> Void) -> Binding<Double> {
        Binding(
            get: { current },
            set: { newValue in session.updateEdit { apply(&$0, newValue) } }
        )
    }

    private func iconButton(
        _ symbol: String, help: String, id: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 28, height: 24)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
    }
}
