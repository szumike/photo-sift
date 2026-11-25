import Foundation

/// Scans a session folder and groups JPEG and ARW files into photos by base name.
public enum FolderScanner {
    public static let darkroomFolderName = "Ciemnia"

    /// Returns the photos of `folder`, sorted by capture date, then by name. Subfolders and other files are ignored.
    public static func scan(folder: URL) throws -> [PhotoItem] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var jpegs: [String: URL] = [:]
        var raws: [String: URL] = [:]
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            let id = url.deletingPathExtension().lastPathComponent
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg": if jpegs[id] == nil { jpegs[id] = url }
            case "arw": if raws[id] == nil { raws[id] = url }
            default: continue
            }
        }

        let darkroomIDs = darkroomRawIDs(in: folder.appendingPathComponent(darkroomFolderName, isDirectory: true))

        let items = Set(jpegs.keys).union(raws.keys).map { id in
            let jpegURL = jpegs[id]
            let rawURL = raws[id]
            return PhotoItem(
                id: id,
                jpegURL: jpegURL,
                rawURL: rawURL,
                sidecarURL: folder.appendingPathComponent("\(id).xmp"),
                isSentToDarkroom: darkroomIDs.contains(id.uppercased()),
                captureDate: (jpegURL ?? rawURL).flatMap { PhotoMetadata.read(from: $0).captureDate }
            )
        }
        return items.sorted(by: precedes)
    }

    private static func precedes(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        switch (lhs.captureDate, rhs.captureDate) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id < rhs.id
        }
    }

    /// Upper-cased base names of `.ARW` files in `Ciemnia/` (extension compared case-insensitively).
    private static func darkroomRawIDs(in directory: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(
            names.compactMap { name -> String? in
                let url = URL(fileURLWithPath: name)
                guard url.pathExtension.lowercased() == "arw" else { return nil }
                return url.deletingPathExtension().lastPathComponent.uppercased()
            }
        )
    }
}
