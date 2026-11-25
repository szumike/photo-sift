import PhotoSiftCore
import SwiftUI

/// The stage in edit mode. "Światło i kolor": the cropped result, with 100% zoom. "Kadr": the whole rotated
/// image with `CropOverlay` (no zoom). Holding M (or the "Przed / po" button) shows the photo without its light and colour changes (crop and straightening stay);
/// the "Przed" label is drawn by `PhotoStage`. Previews are rendered by `LivePreviewRenderer` from the
/// screen-sized preview, never from full resolution.
/// Identifiers: `edit.stage`, `edit.image` (the shown photo), plus those of `CropOverlay`.
struct EditStage: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(ViewState.self) private var viewState

    private struct Loaded {
        let id: String
        /// Whole-canvas image (crop mode or before) rather than the cropped result.
        let canvas: Bool
        let image: CGImage
    }

    /// What the rendered image depends on; the crop rect is irrelevant to it in crop mode.
    private struct RenderKey: Equatable {
        let id: String
        let edit: EditParams?
        /// Crop and colour mode show different geometry, so a switch must re-render even when `edit` is equal.
        let canvas: Bool
    }

    private static let inset: CGFloat = 8

    @State private var renderer = LivePreviewRenderer()
    @State private var shown: Loaded?
    @State private var zoomed: Loaded?
    @State private var cursor = CGPoint.zero

    var body: some View {
        ZStack {
            Palette.stage
            if let item = session.currentPhoto, let params = session.currentEditParams {
                content(item, params)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("edit.stage")
    }

    private func content(_ item: PhotoItem, _ params: EditParams) -> some View {
        let isBefore = viewState.isBeforeHeld
        let isCrop = session.tool == .crop && !session.isEditLocked(item)
        let canvas = isCrop
        let edit = isBefore ? params.withoutLightAndColor : params
        let renderEdit: EditParams? = isCrop ? Self.wholeImage(edit) : edit
        let zoomsIn = viewState.isZoomHeld && !canvas
        let imageSize = session.orientedSize(of: item)
        return GeometryReader { geometry in
            let rect = Self.fitted(imageSize, in: geometry.size)
            ZStack {
                if let shown, shown.id == item.id, shown.canvas == canvas {
                    if zoomsIn, let big = zoomed, big.id == item.id {
                        zoomedImage(big.image, in: geometry.size)
                    } else if canvas {
                        Image(shown.image, scale: 1, label: Text("Zdjęcie"))
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .accessibilityIdentifier("edit.image")
                    } else {
                        Image(shown.image, scale: 1, label: Text("Zdjęcie"))
                            .resizable()
                            .scaledToFit()
                            .padding(Self.inset)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .accessibilityIdentifier("edit.image")
                    }
                }
                if isCrop && !isBefore {
                    CropOverlay(session: session, params: params, imageRect: rect, imageSize: imageSize)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase { track(point, in: geometry.size, imageSize: imageSize) }
            }
            .gesture(zoomGesture(enabled: !canvas, size: geometry.size, imageSize: imageSize))
        }
        .task(id: RenderKey(id: item.id, edit: renderEdit, canvas: canvas)) {
            guard let base = try? await model.loader.preview(for: item) else { return }
            guard let image = await renderer.render(renderEdit, of: base, key: "preview.\(item.id)"),
                  !Task.isCancelled else { return }
            shown = Loaded(id: item.id, canvas: canvas, image: image)
        }
        .task(id: RenderKey(id: zoomsIn ? item.id : "", edit: renderEdit, canvas: canvas)) {
            guard zoomsIn else {
                zoomed = nil
                return
            }
            guard let base = try? await model.loader.fullResolution(for: item) else { return }
            guard let image = await renderer.render(renderEdit, of: base, key: "full.\(item.id)"),
                  !Task.isCancelled else { return }
            zoomed = Loaded(id: item.id, canvas: false, image: image)
        }
    }

    /// The edit with the crop replaced by the whole canvas: straightening, light and colour only.
    private static func wholeImage(_ params: EditParams) -> EditParams {
        var whole = params
        whole.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        return whole
    }

    // MARK: Zoom (colour tool only)

    private func zoomGesture(enabled: Bool, size: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard enabled else { return }
                track(value.location, in: size, imageSize: imageSize)
                viewState.isZoomHeld = true
            }
            .onEnded { _ in
                if enabled { viewState.isZoomHeld = false }
            }
    }

    /// The photo at the zoom level (100% = one image pixel per physical screen pixel) with the point under the cursor kept in place.
    private func zoomedImage(_ image: CGImage, in size: CGSize) -> some View {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let width = CGFloat(image.width) * model.zoomLevel / scale
        let height = CGFloat(image.height) * model.zoomLevel / scale
        let anchor = viewState.zoomPoint
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: width, height: height)
            .position(
                x: origin(cursor.x - anchor.x * width, length: width, container: size.width) + width / 2,
                y: origin(cursor.y - anchor.y * height, length: height, container: size.height) + height / 2
            )
    }

    private func origin(_ proposed: CGFloat, length: CGFloat, container: CGFloat) -> CGFloat {
        length <= container ? (container - length) / 2 : min(0, max(container - length, proposed))
    }

    /// Stores the cursor and its position inside the shown (cropped) result, 0...1, for the zoom.
    private func track(_ point: CGPoint, in size: CGSize, imageSize: CGSize) {
        cursor = point
        guard let image = shown?.image else { return }
        let rect = Self.fitted(CGSize(width: image.width, height: image.height), in: size)
        guard rect.width > 0, rect.height > 0 else { return }
        viewState.zoomPoint = CGPoint(
            x: min(1, max(0, (point.x - rect.minX) / rect.width)),
            y: min(1, max(0, (point.y - rect.minY) / rect.height))
        )
    }

    private static func fitted(_ image: CGSize, in container: CGSize) -> CGRect {
        let available = CGSize(width: container.width - 2 * inset, height: container.height - 2 * inset)
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let ratio = min(available.width / image.width, available.height / image.height)
        let size = CGSize(width: image.width * ratio, height: image.height * ratio)
        return CGRect(
            x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }
}
