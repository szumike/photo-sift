import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ExportPlanEntry: Sendable, Equatable {
    public let item: PhotoItem
    /// Non-identity edit to render; nil means a 1:1 copy.
    public let edit: EditParams?
    public let status: ExportStatus
}

public struct ExportPlan: Sendable, Equatable {
    public let albumURL: URL
    public let entries: [ExportPlanEntry]

    public func count(_ status: ExportStatus) -> Int { entries.filter { $0.status == status }.count }
    public var newCount: Int { count(.notExported) }
    public var changedCount: Int { count(.changed) }
    public var conflictCount: Int { count(.conflict) }
    public var darkroomSkippedCount: Int { count(.skipped(.darkroom)) }
    public var rawOnlySkippedCount: Int { count(.skipped(.rawOnly)) }
    /// Photos marked for deletion, trashed before the files are written.
    public var deletionItems: [PhotoItem] { entries.filter { $0.status == .skipped(.deletion) }.map(\.item) }
    /// Number of files `run` would write.
    public var pendingCount: Int { newCount + changedCount }
}

public struct ExportProgress: Sendable, Equatable {
    public enum Action: Sendable, Equatable { case copying, rendering }
    public let completed: Int
    public let total: Int
    public let currentID: String
    public let action: Action
}

public struct ExportSummary: Sendable, Equatable {
    public var copied = 0
    public var rendered = 0
    public var failed: [String] = []
    public var wasCancelled = false
    /// Photos marked for deletion that were moved to the Trash before writing.
    public var trashed = 0
    /// Ids of marked photos that could not be fully moved to the Trash.
    public var trashFailed: [String] = []
}

/// Remembers who owns each Album file so re-planning only `stat`s files and re-reads the changed ones.
/// An entry is valid while the Album file and the original keep their size and modification date.
final class OwnershipCache: @unchecked Sendable {
    enum Ownership: Equatable, Sendable {
        case identical
        case fingerprint(String)
        case foreign
    }

    struct Signature: Equatable, Sendable {
        let size: Int
        let modified: Date
    }

    private struct Entry {
        let album: Signature
        let original: Signature
        let ownership: Ownership
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var evaluations = 0

    /// How many times file contents were actually read (cache misses).
    var evaluationCount: Int { lock.withLock { evaluations } }

    func ownership(of album: URL, original: URL) -> Ownership? {
        guard let albumSignature = Self.signature(album), let originalSignature = Self.signature(original) else {
            return nil
        }
        let cached = lock.withLock { entries[album.path] }
        if let cached, cached.album == albumSignature, cached.original == originalSignature {
            return cached.ownership
        }
        let ownership = Self.evaluate(album: album, original: original, sizesEqual: albumSignature.size == originalSignature.size)
        lock.withLock {
            evaluations += 1
            entries[album.path] = Entry(album: albumSignature, original: originalSignature, ownership: ownership)
        }
        return ownership
    }

    func invalidate(_ album: URL) {
        lock.withLock { entries[album.path] = nil }
    }

    private static func signature(_ url: URL) -> Signature? {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        return Signature(size: size, modified: modified)
    }

    private static func evaluate(album: URL, original: URL, sizesEqual: Bool) -> Ownership {
        if sizesEqual, FileManager.default.contentsEqual(atPath: album.path, andPath: original.path) {
            return .identical
        }
        if let fingerprint = AlbumExporter.embeddedFingerprint(of: album) { return .fingerprint(fingerprint) }
        return .foreign
    }
}

/// Exports kept photos to `<session>/Album/`. Only adds and updates: nothing in Album/ is ever deleted,
/// and foreign files (conflicts) are never touched.
public struct AlbumExporter: Sendable {
    public static let albumFolderName = "Album"
    public static let markerPath = "photosift:editFingerprint"
    static let namespaceURI = "http://ns.photosift.app/1.0/"
    static let namespacePrefix = "photosift"

    public enum ExportError: Error {
        case unsafeDestination
        case renderFailed
    }

    public let sessionFolder: URL
    let cache = OwnershipCache()

    /// Copies share the ownership cache, so keep one exporter per session to benefit from it.
    public init(sessionFolder: URL) {
        self.sessionFolder = sessionFolder
    }

    private var albumURL: URL {
        sessionFolder.appendingPathComponent(Self.albumFolderName, isDirectory: true)
    }

    /// Computes the status of every item against the real contents of Album/.
    /// `states` carries each photo's edit and darkroom mark, keyed by `PhotoItem.id`.
    public func plan(items: [PhotoItem], states: [PhotoItem.ID: SidecarState]) -> ExportPlan {
        let entries = items.map { item -> ExportPlanEntry in
            let state = states[item.id] ?? SidecarState()
            let edit = state.edit.flatMap { $0.isIdentity ? nil : $0 }
            return ExportPlanEntry(item: item, edit: edit, status: status(of: item, state: state, edit: edit))
        }
        return ExportPlan(albumURL: albumURL, entries: entries)
    }

    private func status(of item: PhotoItem, state: SidecarState, edit: EditParams?) -> ExportStatus {
        if state.markedForDeletion { return .skipped(.deletion) }
        if item.isSentToDarkroom || state.markedForDarkroom || state.photosAssetID != nil { return .skipped(.darkroom) }
        guard let jpegURL = item.jpegURL else { return .skipped(.rawOnly) }

        let destination = albumURL.appendingPathComponent(jpegURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: destination.path) else { return .notExported }

        switch cache.ownership(of: destination, original: jpegURL) {
        case .identical: return edit == nil ? .current : .changed
        case .fingerprint(let fingerprint): return fingerprint == edit?.fingerprint ? .current : .changed
        case .foreign, nil: return .conflict
        }
    }

    /// Writes every `notExported` and `changed` entry. Checks for cancellation between photos.
    public func run(
        plan: ExportPlan,
        progress: @Sendable (ExportProgress) -> Void = { _ in }
    ) async -> ExportSummary {
        var summary = ExportSummary()
        let pending = plan.entries.filter { $0.status == .notExported || $0.status == .changed }
        guard !pending.isEmpty else { return summary }

        do {
            try FileManager.default.createDirectory(at: albumURL, withIntermediateDirectories: true)
        } catch {
            summary.failed = pending.map(\.item.id)
            return summary
        }

        for (index, entry) in pending.enumerated() {
            if Task.isCancelled {
                summary.wasCancelled = true
                break
            }
            // Album/ may have changed since planning; only touch what is still ours or absent.
            let state = SidecarState(edit: entry.edit, markedForDarkroom: false)
            let current = status(of: entry.item, state: state, edit: entry.edit)
            guard current == .notExported || current == .changed, let source = entry.item.jpegURL else {
                continue
            }
            let action: ExportProgress.Action = entry.edit == nil ? .copying : .rendering
            progress(ExportProgress(completed: index, total: pending.count, currentID: entry.item.id, action: action))
            do {
                let destination = albumURL.appendingPathComponent(source.lastPathComponent)
                guard destination.deletingLastPathComponent().standardizedFileURL == albumURL.standardizedFileURL
                else { throw ExportError.unsafeDestination }
                if let edit = entry.edit {
                    try render(source: source, edit: edit, to: destination)
                    summary.rendered += 1
                } else {
                    try copy(source: source, to: destination)
                    summary.copied += 1
                }
            } catch {
                summary.failed.append(entry.item.id)
            }
        }
        return summary
    }

    // MARK: Writing

    private func copy(source: URL, to destination: URL) throws {
        defer { cache.invalidate(destination) }
        try Self.withTemporaryFile(for: destination) { temporary in
            try FileManager.default.copyItem(at: source, to: temporary)
            try Self.install(temporary, at: destination)
        }
    }

    private func render(source: URL, edit: EditParams, to destination: URL) throws {
        defer { cache.invalidate(destination) }
        let image = try EditRenderer.render(url: source, params: edit)

        var properties = Self.sourceProperties(of: source)
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = image.width
        properties[kCGImagePropertyPixelHeight] = image.height
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            properties[kCGImagePropertyExifDictionary] = exif
        }
        properties[kCGImageDestinationLossyCompressionQuality] = 0.95

        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(
            metadata, Self.namespaceURI as CFString, Self.namespacePrefix as CFString, nil
        )
        guard
            CGImageMetadataSetValueWithPath(metadata, nil, Self.markerPath as CFString, edit.fingerprint as CFString)
        else { throw ExportError.renderFailed }

        try Self.withTemporaryFile(for: destination) { temporary in
            guard
                let imageDestination = CGImageDestinationCreateWithURL(
                    temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil
                )
            else { throw ExportError.renderFailed }
            CGImageDestinationAddImageAndMetadata(imageDestination, image, metadata, properties as CFDictionary)
            guard CGImageDestinationFinalize(imageDestination) else { throw ExportError.renderFailed }
            try Self.install(temporary, at: destination)
        }
    }

    /// Atomically puts `temporary` (on the same volume) in place of `destination`.
    private static func install(_ temporary: URL, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    /// Runs `body` with a scratch file URL inside a per-call temporary directory on the destination's volume
    /// (never inside Album/). The directory is removed afterwards, whether `body` succeeded or not.
    private static func withTemporaryFile(for destination: URL, _ body: (URL) throws -> Void) throws {
        let directory = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination.deletingLastPathComponent(), create: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }  // own temporary directory
        try body(directory.appendingPathComponent(destination.lastPathComponent))
    }

    // MARK: Reading

    private static func sourceProperties(of url: URL) -> [CFString: Any] {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [:] }
        return properties
    }

    static func embeddedFingerprint(of url: URL) -> String? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        else { return nil }
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, markerPath as CFString) else { return nil }
        return CGImageMetadataTagCopyValue(tag) as? String
    }
}
