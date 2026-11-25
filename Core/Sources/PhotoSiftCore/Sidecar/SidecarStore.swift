import CoreGraphics
import Foundation
import ImageIO

public enum SidecarError: Error, Equatable {
    case unreadableXMP
    case writeFailed
}

/// Reads and writes `SidecarState` as `photosift:` fields of an XMP sidecar,
/// leaving every other field of an existing file untouched.
public struct SidecarStore: Sendable {
    static let namespace = "http://ns.photosift.app/1.0/"
    static let prefix = "photosift"

    public init() {}

    /// A missing file or a file without `photosift:` fields yields the empty state.
    public func read(at url: URL) throws -> SidecarState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SidecarState() }
        let metadata = try Self.load(url)
        let marked = Self.string(metadata, "markedForDarkroom") == "True"
        let photosAssetID = Self.string(metadata, "photosAssetID")
        guard
            let x = Self.double(metadata, "cropX"), let y = Self.double(metadata, "cropY"),
            let width = Self.double(metadata, "cropWidth"), let height = Self.double(metadata, "cropHeight"),
            let orientation = Self.string(metadata, "orientation").flatMap(CropOrientation.init(rawValue:)),
            let angle = Self.double(metadata, "angle"),
            let temperature = Self.double(metadata, "temperature"),
            let tint = Self.double(metadata, "tint")
        else { return SidecarState(markedForDarkroom: marked, photosAssetID: photosAssetID) }
        let edit = EditParams(
            crop: CGRect(x: x, y: y, width: width, height: height),
            orientation: orientation,
            angle: angle,
            temperature: temperature,
            tint: tint,
            // Edits written before exposure existed have no field: that means 0.
            exposure: Self.double(metadata, "exposure") ?? 0,
            highlights: Self.double(metadata, "highlights") ?? 0,
            shadows: Self.double(metadata, "shadows") ?? 0
        )
        return SidecarState(edit: edit, markedForDarkroom: marked, photosAssetID: photosAssetID)
    }

    /// Writes `state`, keeping foreign fields. An empty state creates no file and
    /// removes a file that holds nothing but `photosift:` fields.
    public func write(_ state: SidecarState, to url: URL) throws {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let isEmpty = state.edit == nil && !state.markedForDarkroom && state.photosAssetID == nil
        if isEmpty && !exists { return }

        let metadata = try exists ? Self.mutable(try Self.load(url)) : CGImageMetadataCreateMutable()
        Self.removePhotoSiftTags(from: metadata)
        if !isEmpty { try Self.register(metadata) }
        if state.markedForDarkroom { try Self.set(metadata, "markedForDarkroom", "True") }
        if let photosAssetID = state.photosAssetID { try Self.set(metadata, "photosAssetID", photosAssetID) }
        if let edit = state.edit {
            try Self.set(metadata, "cropX", Self.format(edit.crop.origin.x))
            try Self.set(metadata, "cropY", Self.format(edit.crop.origin.y))
            try Self.set(metadata, "cropWidth", Self.format(edit.crop.size.width))
            try Self.set(metadata, "cropHeight", Self.format(edit.crop.size.height))
            try Self.set(metadata, "orientation", edit.orientation.rawValue)
            try Self.set(metadata, "angle", Self.format(edit.angle))
            try Self.set(metadata, "temperature", Self.format(edit.temperature))
            try Self.set(metadata, "tint", Self.format(edit.tint))
            try Self.set(metadata, "exposure", Self.format(edit.exposure))
            try Self.set(metadata, "highlights", Self.format(edit.highlights))
            try Self.set(metadata, "shadows", Self.format(edit.shadows))
        }
        try Self.persist(metadata, to: url)
    }

    /// Removes all `photosift:` fields and keeps the rest; deletes the file when nothing else is left.
    public func clearPhotoSiftFields(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let metadata = try Self.mutable(try Self.load(url))
        Self.removePhotoSiftTags(from: metadata)
        try Self.persist(metadata, to: url)
    }

    // MARK: - Helpers

    private static func load(_ url: URL) throws -> CGImageMetadata {
        let data = try Data(contentsOf: url)
        guard let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else {
            throw SidecarError.unreadableXMP
        }
        return metadata
    }

    private static func mutable(_ metadata: CGImageMetadata) throws -> CGMutableImageMetadata {
        guard let copy = CGImageMetadataCreateMutableCopy(metadata) else { throw SidecarError.unreadableXMP }
        return copy
    }

    private static func register(_ metadata: CGMutableImageMetadata) throws {
        var error: Unmanaged<CFError>?
        let ok = CGImageMetadataRegisterNamespaceForPrefix(
            metadata, namespace as CFString, prefix as CFString, &error
        )
        // Already registered is not a failure.
        if !ok, let error, CFErrorGetCode(error.takeRetainedValue()) != CGImageMetadataErrors.prefixConflict.rawValue {
            throw SidecarError.writeFailed
        }
    }

    private static func set(_ metadata: CGMutableImageMetadata, _ name: String, _ value: String) throws {
        guard CGImageMetadataSetValueWithPath(metadata, nil, "\(prefix):\(name)" as CFString, value as CFString) else {
            throw SidecarError.writeFailed
        }
    }

    private static func photoSiftTags(_ metadata: CGImageMetadata) -> [CGImageMetadataTag] {
        let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] ?? []
        return tags.filter { CGImageMetadataTagCopyNamespace($0) as String? == namespace }
    }

    private static func removePhotoSiftTags(from metadata: CGMutableImageMetadata) {
        for tag in photoSiftTags(metadata) {
            guard let name = CGImageMetadataTagCopyName(tag) as String? else { continue }
            CGImageMetadataRemoveTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString)
        }
    }

    /// Writes the XMP atomically, or deletes the file when no tags remain.
    private static func persist(_ metadata: CGMutableImageMetadata, to url: URL) throws {
        // ImageIO tags a parsed packet with its own bookkeeping; it is not file content.
        CGImageMetadataRemoveTagWithPath(metadata, nil, "iio:hasXMP" as CFString)
        let remaining = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] ?? []
        if remaining.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                // The file held only fields this app wrote, so it is app-owned.
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        guard let data = CGImageMetadataCreateXMPData(metadata, nil) as Data? else { throw SidecarError.writeFailed }
        try data.write(to: url, options: .atomic)
    }

    private static func string(_ metadata: CGImageMetadata, _ name: String) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString) else {
            return nil
        }
        return CGImageMetadataTagCopyValue(tag) as? String
    }

    private static func double(_ metadata: CGImageMetadata, _ name: String) -> Double? {
        string(metadata, name).flatMap(Double.init)
    }

    /// Round-trips every `Double` exactly.
    private static func format(_ value: Double) -> String { "\(value + 0)" }
}
