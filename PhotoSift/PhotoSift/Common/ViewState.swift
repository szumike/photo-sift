import CoreGraphics
import Observation
import PhotoSiftCore

/// View-only state shared by the screens; nothing here is persisted or affects files.
/// Injected with `.environment(viewState)`.
@MainActor @Observable
final class ViewState {
    /// Z is held (set by `KeyboardRouter`) or the mouse button is held on the photo (set by the photo view).
    var isZoomHeld = false
    /// M is held: show the photo without its edit.
    var isBeforeHeld = false
    /// B is held: show the photo's RAW decode.
    var isRawHeld = false
    /// Zoom anchor, normalized 0...1 in the photo; written by the photo view on mouse move.
    var zoomPoint = CGPoint(x: 0.5, y: 0.5)
    /// F mode: only the current photo fills the window (toolbar, filmstrip and info panel hidden).
    var isPresenting = false
    /// Column count of the grid; written by `GridView`, read by `KeyboardRouter` for ↑ and ↓.
    var gridColumns = 6
    /// The message currently shown (from `Session.toast` or the app itself).
    private(set) var toast: Toast?

    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func present(_ toast: Toast, duration: Duration = .seconds(3), onExpire: (@MainActor () -> Void)? = nil) {
        toastTask?.cancel()
        self.toast = toast
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.toast = nil
            onExpire?()
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func resetHolds() {
        isZoomHeld = false
        isBeforeHeld = false
        isRawHeld = false
    }
}
