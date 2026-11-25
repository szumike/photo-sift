import Foundation

public struct TrashResult: Sendable {
    public struct Failure: Sendable {
        public let url: URL
        public let message: String
    }

    public var trashed: [URL] = []
    public var failed: [Failure] = []

    public var isComplete: Bool { failed.isEmpty }
}

public struct PhotoTrasher: Sendable {
    public init() {}

    /// Moves the photo's existing JPEG, ARW and XMP files to the Trash. Never touches `Album/` or `Ciemnia/`.
    public func trash(_ item: PhotoItem) -> TrashResult {
        let fileManager = FileManager.default
        var result = TrashResult()
        let candidates = [item.jpegURL, item.rawURL, item.sidecarURL].compactMap { $0 }
        for url in candidates where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                result.trashed.append(url)
            } catch {
                result.failed.append(.init(url: url, message: error.localizedDescription))
            }
        }
        return result
    }
}
