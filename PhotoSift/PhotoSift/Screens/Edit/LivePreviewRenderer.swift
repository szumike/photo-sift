import CoreImage
import PhotoSiftCore

/// Renders the live edit preview through `EditRenderer` (the export pipeline, shared CIContext) off the main actor.
/// Requests are coalesced by the caller: a view task per parameter set is cancelled when newer parameters
/// arrive, and a request that is cancelled before its turn on this actor returns without rendering.
actor LivePreviewRenderer {
    private var source: (key: String, image: CIImage)?

    /// Renders `edit` onto `base`; `nil` returns the unedited image. `key` identifies `base` so its
    /// `CIImage` is built once. Returns nil when cancelled or when rendering fails.
    func render(_ edit: EditParams?, of base: CGImage, key: String) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        guard let edit else { return base }
        if source?.key != key { source = (key, CIImage(cgImage: base)) }
        guard let source, let rendered = try? EditRenderer.render(EditRenderer.apply(edit, to: source.image)) else {
            return nil
        }
        return Task.isCancelled ? nil : rendered
    }
}
