import PhotoSiftCore
import SwiftUI

/// The crop rectangle over the whole rotated image: dimmed outside, rule-of-thirds grid, four corner handles,
/// move by dragging inside, and the size label in original JPEG pixels. The ratio stays 3:2 / 2:3 and the crop
/// stays inside the rotated image (`CropGeometry.constrainCrop`).
/// Identifiers: `crop.overlay` (the dimmed area), `crop.box`, `crop.size`, `crop.handle.nw|ne|sw|se`.
struct CropOverlay: View {
    let session: Session
    let params: EditParams
    /// Where the (rotated) image canvas is drawn in the stage.
    let imageRect: CGRect
    let imageSize: CGSize

    private enum Handle: String, CaseIterable {
        case nw, ne, sw, se
        var isWest: Bool { self == .nw || self == .sw }
        var isNorth: Bool { self == .nw || self == .ne }
    }

    @State private var dragStart: CGRect?

    private static let space = "crop.space"
    private static let minimumWidth = 0.1

    private var box: CGRect {
        CGRect(
            x: imageRect.minX + params.crop.minX * imageRect.width,
            y: imageRect.minY + params.crop.minY * imageRect.height,
            width: params.crop.width * imageRect.width,
            height: params.crop.height * imageRect.height
        )
    }

    var body: some View {
        let box = box
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(imageRect)
                path.addRect(box)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("crop.overlay")

            grid(in: box)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
                .allowsHitTesting(false)
            Rectangle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                .frame(width: box.width, height: box.height)
                .contentShape(Rectangle())
                .position(x: box.midX, y: box.midY)
                .gesture(moveGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("crop.box")
            ForEach(Handle.allCases, id: \.self) { handle in
                handleView(handle, at: CGPoint(x: handle.isWest ? box.minX : box.maxX, y: handle.isNorth ? box.minY : box.maxY))
            }
            sizeLabel(in: box)
        }
        .coordinateSpace(name: Self.space)
        .onDisappear { endDrag() }
    }

    private func grid(in box: CGRect) -> Path {
        Path { path in
            for fraction in [1.0 / 3, 2.0 / 3] {
                path.move(to: CGPoint(x: box.minX + box.width * fraction, y: box.minY))
                path.addLine(to: CGPoint(x: box.minX + box.width * fraction, y: box.maxY))
                path.move(to: CGPoint(x: box.minX, y: box.minY + box.height * fraction))
                path.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * fraction))
            }
        }
    }

    private func sizeLabel(in box: CGRect) -> some View {
        let width = Int((params.crop.width * imageSize.width).rounded())
        let height = Int((params.crop.height * imageSize.height).rounded())
        let ratio = params.orientation == .landscape ? "3:2" : "2:3"
        return Text("\(ratio) · \(width) × \(height)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(.black.opacity(0.6), in: Capsule())
            .position(x: box.midX, y: min(box.maxY - 22, imageRect.maxY - 22))
            .allowsHitTesting(false)
            .accessibilityIdentifier("crop.size")
    }

    private func handleView(_ handle: Handle, at point: CGPoint) -> some View {
        Rectangle()
            .fill(.white)
            .frame(width: 12, height: 12)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        beginDrag()
                        resize(handle, to: value)
                    }
                    .onEnded { _ in endDrag() }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Uchwyt kadru")
            .accessibilityIdentifier("crop.handle.\(handle.rawValue)")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                beginDrag()
                let start = dragStart ?? params.crop
                dragStart = start
                var moved = start
                moved.origin.x += value.translation.width / imageRect.width
                moved.origin.y += value.translation.height / imageRect.height
                setCrop(moved)
            }
            .onEnded { _ in endDrag() }
    }

    /// Keeps the opposite corner fixed and sizes the crop to the pointer at the exact ratio.
    private func resize(_ handle: Handle, to value: DragGesture.Value) {
        let start = dragStart ?? params.crop
        dragStart = start
        let ratio = CropGeometry.aspectRatio(for: params.orientation)
        let aspect = imageSize.width / imageSize.height
        let anchorX = handle.isWest ? start.maxX : start.minX
        let anchorY = handle.isNorth ? start.maxY : start.minY
        let pointerX = (value.location.x - imageRect.minX) / imageRect.width
        let pointerY = (value.location.y - imageRect.minY) / imageRect.height
        let dirX: CGFloat = handle.isWest ? -1 : 1
        let dirY: CGFloat = handle.isNorth ? -1 : 1
        // Normalized height = width * aspect / ratio.
        let width = min(1, max(Self.minimumWidth, max(dirX * (pointerX - anchorX), dirY * (pointerY - anchorY) * ratio / aspect)))
        let height = width * aspect / ratio
        setCrop(CGRect(
            x: handle.isWest ? anchorX - width : anchorX,
            y: handle.isNorth ? anchorY - height : anchorY,
            width: width, height: height
        ))
    }

    private func beginDrag() {
        guard dragStart == nil else { return }
        session.beginEditGesture()
    }

    private func endDrag() {
        dragStart = nil
        session.endEditGesture()
    }

    private func setCrop(_ crop: CGRect) {
        let fitted = CropGeometry.constrainCrop(
            crop, orientation: params.orientation, angle: params.angle, imageSize: imageSize
        )
        session.updateEdit { $0.crop = fitted }
    }
}
