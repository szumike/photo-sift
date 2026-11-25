import PhotoSiftCore
import SwiftUI

/// "Kadr": orientation (3:2 / 2:3, no shortcut) and straightening angle.
/// Identifiers: `edit.orientation.landscape|portrait`, `edit.angle`, `edit.angle.value`.
struct CropSection: View {
    let session: Session

    var body: some View {
        let params = session.currentEditParams
        VStack(alignment: .leading, spacing: 10) {
            EditSectionLabel("Orientacja")
            HStack(spacing: 2) {
                orientationButton("3:2", symbol: "rectangle", .landscape, current: params?.orientation)
                orientationButton("2:3", symbol: "rectangle.portrait", .portrait, current: params?.orientation)
            }
            .padding(2)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            EditSectionLabel("Prostowanie")
                .padding(.top, 6)
            EditSlider(
                title: "Kąt", id: "edit.angle",
                value: Binding(
                    get: { params?.angle ?? 0 },
                    set: { setAngle($0) }
                ),
                range: -45...45, step: 0.1, neutral: 0,
                format: { String(format: "%.1f°", $0 + 0) },
                onEditingChanged: { isEditing in
                    if isEditing { session.beginEditGesture() } else { session.endEditGesture() }
                }
            )
        }
        .padding(.top, 16)
    }

    private func orientationButton(
        _ title: String, symbol: String, _ orientation: CropOrientation, current: CropOrientation?
    ) -> some View {
        let isSelected = current == orientation
        return Button {
            update { $0.orientation = orientation }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(isSelected ? Palette.primary : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(orientation == .landscape ? "Poziom 3:2" : "Pion 2:3")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("edit.orientation.\(orientation.rawValue)")
    }

    private func setAngle(_ angle: Double) {
        update { $0.angle = angle }
    }

    /// Applies `change`, then fits the crop to the new orientation and angle.
    private func update(_ change: (inout EditParams) -> Void) {
        guard let item = session.currentPhoto else { return }
        let size = session.orientedSize(of: item)
        session.updateEdit { params in
            change(&params)
            let fitted = CropGeometry.constrainCrop(
                params.crop, orientation: params.orientation, angle: params.angle, imageSize: size
            )
            if !Self.isClose(fitted, params.crop) { params.crop = fitted }
        }
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9
            && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
    }
}
