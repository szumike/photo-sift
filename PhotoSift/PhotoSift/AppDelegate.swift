import AppKit

/// Receives photos opened from Finder ("Open With" → Photo Sift). A file that arrives before
/// the window is up (cold launch) waits until `attach(_:)`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingPhoto: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let model {
            model.openPhoto(url)
        } else {
            pendingPhoto = url
        }
    }

    /// Connects the model and opens a photo that arrived before it.
    func attach(_ model: AppModel) {
        self.model = model
        if let pendingPhoto {
            self.pendingPhoto = nil
            model.openPhoto(pendingPhoto)
        }
    }
}
