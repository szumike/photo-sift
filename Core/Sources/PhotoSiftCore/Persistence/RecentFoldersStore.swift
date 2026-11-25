import Foundation

public struct RecentFolder: Codable, Hashable, Sendable {
    public var name: String
    public var path: String
    public var photoCount: Int
    public var date: Date

    public init(name: String, path: String, photoCount: Int, date: Date) {
        self.name = name
        self.path = path
        self.photoCount = photoCount
        self.date = date
    }
}

/// Keeps up to `limit` recently opened folders, newest first.
public struct RecentFoldersStore {
    public static let limit = 8
    static let key = "recentFolders"

    private let defaults: UserDefaults
    private let folderExists: @Sendable (String) -> Bool

    public init(
        defaults: UserDefaults = .standard,
        folderExists: @escaping @Sendable (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    ) {
        self.defaults = defaults
        self.folderExists = folderExists
    }

    /// Newest first; folders that no longer exist on disk are skipped.
    public func folders() -> [RecentFolder] {
        stored().filter { folderExists($0.path) }
    }

    /// Moves an already known path to the front instead of duplicating it.
    public func record(_ folder: RecentFolder) {
        var updated = stored().filter { $0.path != folder.path }
        updated.insert(folder, at: 0)
        save(Array(updated.prefix(Self.limit)))
    }

    private func stored() -> [RecentFolder] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([RecentFolder].self, from: data)) ?? []
    }

    private func save(_ folders: [RecentFolder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
