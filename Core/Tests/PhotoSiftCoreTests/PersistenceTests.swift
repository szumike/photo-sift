import Foundation
import Testing
@testable import PhotoSiftCore

@Suite("PersistenceTests")
struct PersistenceTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "PersistenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func folder(_ path: String, count: Int = 10) -> RecentFolder {
        RecentFolder(name: (path as NSString).lastPathComponent, path: path, photoCount: count, date: Date(timeIntervalSince1970: 1_000))
    }

    @Test func resumeIsKeyedByFolderPath() {
        withDefaults { defaults in
            let store = ResumeStore(defaults: defaults)
            let a = URL(fileURLWithPath: "/photos/a")
            let b = URL(fileURLWithPath: "/photos/b")
            #expect(store.lastPhotoID(in: a) == nil)
            store.setLastPhotoID("DSC00001", in: a)
            store.setLastPhotoID("DSC00002", in: b)
            store.setLastPhotoID("DSC00003", in: a)
            #expect(store.lastPhotoID(in: a) == "DSC00003")
            #expect(store.lastPhotoID(in: b) == "DSC00002")
            #expect(ResumeStore(defaults: defaults).lastPhotoID(in: a) == "DSC00003")
        }
    }

    @Test func recentFoldersKeepFieldsNewestFirstAndDeduplicate() {
        withDefaults { defaults in
            let store = RecentFoldersStore(defaults: defaults, folderExists: { _ in true })
            store.record(folder("/p/one", count: 3))
            store.record(folder("/p/two"))
            store.record(folder("/p/one", count: 5))
            let folders = store.folders()
            #expect(folders.map(\.path) == ["/p/one", "/p/two"])
            #expect(folders[0] == RecentFolder(name: "one", path: "/p/one", photoCount: 5, date: Date(timeIntervalSince1970: 1_000)))
        }
    }

    @Test func recentFoldersAreCappedAtEight() {
        withDefaults { defaults in
            let store = RecentFoldersStore(defaults: defaults, folderExists: { _ in true })
            for index in 0..<10 { store.record(folder("/p/\(index)")) }
            let paths = store.folders().map(\.path)
            #expect(paths.count == 8)
            #expect(paths.first == "/p/9")
            #expect(paths.last == "/p/2")
        }
    }

    @Test func missingFoldersAreSkippedOnRead() throws {
        try withDefaults { defaults in
            let existing = FileManager.default.temporaryDirectory
                .appendingPathComponent("PersistenceTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: existing) }
            let store = RecentFoldersStore(defaults: defaults)
            store.record(folder(existing.path))
            store.record(folder("/definitely/not/here-\(UUID().uuidString)"))
            #expect(store.folders().map(\.path) == [existing.path])
        }
    }

    @Test func resumeEntriesAreCappedKeepingMostRecent() {
        withDefaults { defaults in
            let store = ResumeStore(defaults: defaults)
            let total = ResumeStore.maxEntries + 5
            for index in 0..<total {
                store.setLastPhotoID("P\(index)", in: URL(fileURLWithPath: "/photos/\(index)"))
            }
            // Touching an old folder makes it recent again.
            store.setLastPhotoID("again", in: URL(fileURLWithPath: "/photos/6"))
            store.setLastPhotoID("last", in: URL(fileURLWithPath: "/photos/new"))
            let stored = defaults.dictionary(forKey: ResumeStore.key) as? [String: String]
            #expect(stored?.count == ResumeStore.maxEntries)
            #expect(store.lastPhotoID(in: URL(fileURLWithPath: "/photos/0")) == nil)
            #expect(store.lastPhotoID(in: URL(fileURLWithPath: "/photos/6")) == "again")
            #expect(store.lastPhotoID(in: URL(fileURLWithPath: "/photos/new")) == "last")
        }
    }
}
