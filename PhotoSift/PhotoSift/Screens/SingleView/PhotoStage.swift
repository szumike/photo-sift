import CoreImage
import PhotoSiftCore
import SwiftUI

/// The area above the filmstrip: the photo (with 100% zoom under the cursor), `EditStage` while editing,
/// or the empty-filter message.
/// Identifiers: `stage`, `stage.photo`, `stage.zoomLabel`, `stage.beforeLabel`, `stage.rawLabel`, `stage.rawImage`, `stage.showAll`.
struct PhotoStage: View {
    let session: Session
    let albumStatuses: [String: ExportStatus]
    @Environment(AppModel.self) private var model

    private struct LoadedImage {
        let id: String
        let image: CGImage
    }

    /// What the displayed image depends on: the photo and the edit applied to it.
    private struct ImageKey: Equatable {
        let id: String
        let edit: EditParams?
    }

    @State private var fitted: LoadedImage?
    @State private var full: LoadedImage?
    /// RAW decode of the photo shown while B is held; kept after release so a quick re-hold is instant.
    @State private var raw: LoadedImage?
    /// Cursor position in the stage, used to anchor the 100% zoom.
    @State private var cursor = CGPoint.zero

    private var viewState: ViewState { model.viewState }

    var body: some View {
        ZStack {
            Palette.stage
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stage")
    }

    @ViewBuilder
    private var content: some View {
        if let item = session.currentPhoto {
            ZStack {
                if session.mode == .edit {
                    EditStage(session: session)
                } else {
                    photo(item)
                }
                if viewState.isRawHeld, item.rawURL != nil { rawImage(item) }
                labels(item)
            }
        } else if session.photos.isEmpty {
            Text("Brak zdjęć")
                .font(.system(size: 17, weight: .semibold))
        } else {
            emptyFilter
        }
    }

    private var emptyFilter: some View {
        VStack(spacing: 8) {
            Text(session.filter == .darkroom ? "Brak zdjęć w Ciemni" : "Brak edytowanych zdjęć")
                .font(.system(size: 17, weight: .semibold))
            Button("Pokaż wszystkie") { session.setFilter(.all) }
                .padding(.top, 8)
                .accessibilityIdentifier("stage.showAll")
        }
    }

    // MARK: Photo

    private func photo(_ item: PhotoItem) -> some View {
        let zoomed = viewState.isZoomHeld
        let stored = session.state(of: item.id).edit
        let edit = viewState.isBeforeHeld ? stored?.withoutLightAndColor : stored
        return GeometryReader { geometry in
            ZStack {
                if let image = fitted, image.id == item.id {
                    if zoomed, let big = full, big.id == item.id {
                        zoomedImage(big.image, in: geometry.size)
                    } else {
                        Image(decorative: image.image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase { track(point, in: geometry.size) }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        track(value.location, in: geometry.size)
                        viewState.isZoomHeld = true
                    }
                    .onEnded { _ in viewState.isZoomHeld = false }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stage.photo")
        .task(id: ImageKey(id: item.id, edit: edit)) {
            guard let base = try? await model.loader.preview(for: item) else { return }
            let image = await Self.apply(edit, to: base)
            guard !Task.isCancelled else { return }
            fitted = LoadedImage(id: item.id, image: image)
        }
        .task(id: ImageKey(id: zoomed ? item.id : "", edit: edit)) {
            guard zoomed else {
                full = nil
                return
            }
            guard let base = try? await model.loader.fullResolution(for: item) else { return }
            let image = await Self.apply(edit, to: base)
            guard !Task.isCancelled else { return }
            full = LoadedImage(id: item.id, image: image)
        }
    }

    /// The plain RAW decode, fitted like the preview, covering the photo (browse and edit mode alike).
    private func rawImage(_ item: PhotoItem) -> some View {
        ZStack {
            Palette.stage
            if let raw, raw.id == item.id {
                Image(decorative: raw.image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .accessibilityIdentifier("stage.rawImage")
            }
        }
        .task(id: item.id) {
            guard raw?.id != item.id else { return }
            guard let image = try? await model.loader.rawPreview(for: item, maxPixelSize: ImageLoader.defaultPreviewMaxPixelSize),
                  !Task.isCancelled else { return }
            raw = LoadedImage(id: item.id, image: image)
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

    /// Keeps the zoomed image covering the stage; one smaller than the stage is centred.
    private func origin(_ proposed: CGFloat, length: CGFloat, container: CGFloat) -> CGFloat {
        length <= container ? (container - length) / 2 : min(0, max(container - length, proposed))
    }

    /// Stores the cursor and its position inside the photo (0...1) for the zoom.
    private func track(_ point: CGPoint, in size: CGSize) {
        cursor = point
        guard let image = fitted?.image else { return }
        let rect = Self.fittedRect(of: CGSize(width: image.width, height: image.height), in: size, inset: 8)
        guard rect.width > 0, rect.height > 0 else { return }
        viewState.zoomPoint = CGPoint(
            x: min(1, max(0, (point.x - rect.minX) / rect.width)),
            y: min(1, max(0, (point.y - rect.minY) / rect.height))
        )
    }

    private static func fittedRect(of image: CGSize, in container: CGSize, inset: CGFloat) -> CGRect {
        let available = CGSize(width: container.width - 2 * inset, height: container.height - 2 * inset)
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let ratio = min(available.width / image.width, available.height / image.height)
        let size = CGSize(width: image.width * ratio, height: image.height * ratio)
        return CGRect(
            x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    /// Renders the edit onto the decoded image off the main actor; without an edit the image is returned as is.
    @concurrent nonisolated private static func apply(_ edit: EditParams?, to image: CGImage) async -> CGImage {
        guard let edit else { return image }
        let edited = EditRenderer.apply(edit, to: CIImage(cgImage: image))
        return (try? EditRenderer.render(edited)) ?? image
    }

    // MARK: Labels

    private func labels(_ item: PhotoItem) -> some View {
        ZStack(alignment: .top) {
            HStack {
                StatusBadges(
                    item: item, session: session, albumStatus: albumStatuses[item.id],
                    showsLock: session.mode == .edit
                )
                Spacer()
            }
            .padding(.top, 14)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            HStack {
                Spacer()
                if viewState.isRawHeld {
                    pill(rawLabel(for: item), id: "stage.rawLabel", foreground: Color(white: 0.07), background: Color(white: 0.94, opacity: 0.92))
                } else if viewState.isBeforeHeld {
                    pill("Przed", id: "stage.beforeLabel", foreground: Color(white: 0.07), background: Color(white: 0.94, opacity: 0.92))
                } else if viewState.isZoomHeld && zoomIsActive(for: item) {
                    pill(model.zoomLabel, id: "stage.zoomLabel", foreground: .white, background: Color(red: 24 / 255, green: 24 / 255, blue: 26 / 255, opacity: 0.86))
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func rawLabel(for item: PhotoItem) -> String {
        guard item.rawURL != nil else { return "Brak RAW" }
        return raw?.id == item.id ? "RAW" : "RAW…"
    }

    /// Zoom works everywhere except the crop tool on an editable photo (same rule as `EditStage`).
    private func zoomIsActive(for item: PhotoItem) -> Bool {
        session.mode == .browse || session.tool != .crop || session.isEditLocked(item)
    }

    private func pill(_ text: String, id: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(background, in: Capsule())
            .accessibilityIdentifier(id)
    }
}
