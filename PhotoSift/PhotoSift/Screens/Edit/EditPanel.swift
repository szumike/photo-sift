import PhotoSiftCore
import SwiftUI

/// The edit inspector shown instead of the "Stan" card in edit mode.
/// Identifiers: `edit.panel`, `edit.tab.color|crop`, `edit.before`, `edit.reset`,
/// plus those of `WhiteBalanceSection`, `CropSection` and `LockedEditPanel`.
struct EditPanel: View {
    let session: Session
    @Environment(ViewState.self) private var viewState

    var body: some View {
        Group {
            if let item = session.currentPhoto, session.isEditLocked(item) {
                LockedEditPanel(session: session, item: item)
            } else {
                editor
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("edit.panel")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabs
            switch session.tool {
            case .color: WhiteBalanceSection(session: session)
            case .crop: CropSection(session: session)
            }
            Spacer(minLength: 18)
            HStack(spacing: 6) {
                beforeButton
                resetButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Pieces

    private var tabs: some View {
        HStack(spacing: 2) {
            tab("Światło i kolor", key: "E", tool: .color, id: "edit.tab.color")
            tab("Kadr", key: "R", tool: .crop, id: "edit.tab.crop")
        }
        .padding(2)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tab(_ title: String, key: String, tool: EditTool, id: String) -> some View {
        let isSelected = session.tool == tool
        return Button {
            session.enterEdit(tool: tool)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text(key).foregroundStyle(Palette.secondaryText)
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(isSelected ? Palette.primary : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private var beforeButton: some View {
        // Held, not clicked: the state is on while the mouse button is down (M does the same).
        footerLabel("Przed / po", key: "M")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in viewState.isBeforeHeld = true }
                    .onEnded { _ in viewState.isBeforeHeld = false }
            )
            .help("Przytrzymaj")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Przed / po")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("edit.before")
    }

    private var resetButton: some View {
        let isEdited = session.currentPhoto.map(session.isEdited) ?? false
        return Button {
            session.resetEdit()
        } label: {
            footerLabel("Resetuj", key: "⇧⌘R")
        }
        .buttonStyle(.plain)
        .disabled(!isEdited)
        .opacity(isEdited ? 1 : 0.4)
        .help("Resetuj edycję (⇧⌘R)")
        .accessibilityIdentifier("edit.reset")
    }

    private func footerLabel(_ title: String, key: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 4)
            Text(key).foregroundStyle(Palette.secondaryText)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}

/// A labelled slider (no tick marks) with a value readout; double-click returns it to `neutral`.
/// `onEditingChanged` reports the start and end of a drag (an undo step on the session).
/// Identifiers: `<id>` (slider), `<id>.value` (readout).
struct EditSlider: View {
    let title: String
    let id: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let neutral: Double
    var track: SliderTrack = .plain
    let format: (Double) -> String
    let onEditingChanged: (Bool) -> Void
    /// Arrow-key and accessibility increment; defaults to the drag `step`.
    var keyStep: Double?

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .accessibilityIdentifier("\(id).value")
            }
            .font(.system(size: 12))
            RangeSlider(
                value: $value, range: range, step: step, keyStep: keyStep ?? step,
                track: track, onEditingChanged: onEditingChanged
            )
                .simultaneousGesture(TapGesture(count: 2).onEnded { value = neutral })
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        }
    }
}

/// Section caption used by the edit sections.
struct EditSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.secondaryText)
    }
}
