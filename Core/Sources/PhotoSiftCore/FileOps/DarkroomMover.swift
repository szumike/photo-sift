import Foundation

public struct DarkroomReport: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let id: String
        public let message: String
    }

    /// Ids whose ARW (and XMP, if present) now sit in `Ciemnia/`.
    public var moved: [String] = []
    /// Ids skipped because a target file already exists in `Ciemnia/`; nothing was touched.
    public var conflicts: [String] = []
    /// Ids skipped because the photo has no ARW in the session folder.
    public var withoutRaw: [String] = []
    public var failures: [Failure] = []
}

/// Moves ARW and XMP of photos to `<session folder>/Ciemnia/`. JPEGs stay in place
/// and existing files in `Ciemnia/` are never overwritten.
public struct DarkroomMover: Sendable {
    static let folderName = "Ciemnia"

    private let sidecarStore = SidecarStore()

    private let sessionFolder: URL

    /// - Parameter sessionFolder: only files lying directly in this folder are moved.
    public init(sessionFolder: URL) {
        self.sessionFolder = sessionFolder
    }

    public func send(_ items: [PhotoItem]) -> DarkroomReport {
        var report = DarkroomReport()
        let fileManager = FileManager.default

        for item in items {
            guard let rawURL = item.rawURL else {
                report.withoutRaw.append(item.id)
                continue
            }
            let root = sessionFolder.standardizedFileURL
            guard
                rawURL.deletingLastPathComponent().standardizedFileURL == root,
                item.sidecarURL.deletingLastPathComponent().standardizedFileURL == root
            else {
                report.failures.append(.init(id: item.id, message: "Plik poza folderem sesji"))
                continue
            }
            let darkroom = root.appendingPathComponent(Self.folderName, isDirectory: true)
            let hasSidecar = fileManager.fileExists(atPath: item.sidecarURL.path)

            let rawTarget = darkroom.appendingPathComponent(rawURL.lastPathComponent)
            let sidecarTarget = darkroom.appendingPathComponent(item.sidecarURL.lastPathComponent)
            if fileManager.fileExists(atPath: rawTarget.path)
                || (hasSidecar && fileManager.fileExists(atPath: sidecarTarget.path))
            {
                report.conflicts.append(item.id)
                continue
            }

            do {
                try fileManager.createDirectory(at: darkroom, withIntermediateDirectories: true)
                try fileManager.moveItem(at: rawURL, to: rawTarget)
                if hasSidecar {
                    try fileManager.moveItem(at: item.sidecarURL, to: sidecarTarget)
                    try sidecarStore.clearPhotoSiftFields(at: sidecarTarget)
                }
                report.moved.append(item.id)
            } catch {
                report.failures.append(.init(id: item.id, message: error.localizedDescription))
            }
        }
        return report
    }
}
