import Foundation

/// Remembers the last viewed photo of each folder, keyed by folder path.
public struct ResumeStore {
    static let key = "resume.lastPhotos"
    static let orderKey = "resume.folderOrder"
    /// Folders remembered at most; the least recently used are dropped first.
    static let maxEntries = 200

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastPhotoID(in folder: URL) -> String? {
        entries[folder.standardizedFileURL.path]
    }

    public func setLastPhotoID(_ id: String, in folder: URL) {
        let path = folder.standardizedFileURL.path
        var updated = entries
        updated[path] = id
        var order = (defaults.stringArray(forKey: Self.orderKey) ?? []).filter { $0 != path && updated[$0] != nil }
        order.append(path)
        for known in updated.keys where !order.contains(known) { order.insert(known, at: 0) }
        while order.count > Self.maxEntries { updated[order.removeFirst()] = nil }
        defaults.set(updated, forKey: Self.key)
        defaults.set(order, forKey: Self.orderKey)
    }

    private var entries: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
