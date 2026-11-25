import Foundation
import Testing
import PhotoSiftTestSupport
@testable import PhotoSiftCore

private final class FakeImporter: PhotosImporting, @unchecked Sendable {
    var existing: Set<String> = []
    var error: PhotosImportError?
    private(set) var calls: [(ids: [String], album: String)] = []

    func importRaws(_ items: [(id: String, rawURL: URL)], albumTitle: String) async throws -> PhotosImportReport {
        if let error { throw error }
        calls.append((items.map(\.id), albumTitle))
        var report = PhotosImportReport()
        for item in items {
            let identifier = "asset-\(item.id)-\(calls.count)"
            existing.insert(identifier)
            report.assetIDs[item.id] = identifier
        }
        return report
    }

    func assetExists(_ localIdentifier: String) -> Bool { existing.contains(localIdentifier) }
}

@MainActor
@Suite("SessionPhotosTests")
struct SessionPhotosTests {
    private func make(
        _ spec: FixtureFolder.Spec, importer: FakeImporter
    ) throws -> (Session, URL) {
        let fixture = try FixtureFolder.make(spec)
        return (try Session(folder: fixture.url, photosImporter: importer), fixture.url)
    }

    private func exists(_ folder: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    @Test func photosTargetRecordsAssetAndKeepsFiles() async throws {
        let importer = FakeImporter()
        let (session, folder) = try make(.init(pairs: ["A1", "A2"]), importer: importer)
        session.toggleDarkroom()
        await session.sendToDarkroom(target: .photos)

        #expect(importer.calls.count == 1)
        #expect(importer.calls[0].ids == ["A1"])
        #expect(importer.calls[0].album == folder.lastPathComponent)
        #expect(exists(folder, "A1.ARW") && exists(folder, "A1.JPG"))
        #expect(!exists(folder, "Ciemnia"))
        let stored = try SidecarStore().read(at: folder.appendingPathComponent("A1.xmp"))
        #expect(stored.photosAssetID == "asset-A1-1")
        #expect(stored.markedForDarkroom)

        let item = try #require(session.photo(id: "A1"))
        #expect(session.isSent(item) && session.isInPhotos(item) && !item.isSentToDarkroom)
        #expect(session.isEditLocked(item))
        #expect(session.darkroomCount == 0)
        #expect(session.exportPlan().entries.first { $0.item.id == "A1" }?.status == .skipped(.darkroom))
        #expect(session.toast?.text == "Dodano 1 plik RAW do Zdjęć")
        #expect(session.toast?.subtext?.contains("Album „\(folder.lastPathComponent)”") == true)
    }

    @Test func assetIDSurvivesReopeningTheFolder() async throws {
        let importer = FakeImporter()
        let (session, folder) = try make(.init(pairs: ["A1"]), importer: importer)
        session.toggleDarkroom()
        await session.sendToDarkroom(target: .photos)
        let reopened = try Session(folder: folder, photosImporter: importer)
        #expect(reopened.isInPhotos(try #require(reopened.photo(id: "A1"))))
        #expect(reopened.darkroomCount == 0)
    }

    @Test func sentPhotoIsNotImportedAgainAndShowsToast() async throws {
        let importer = FakeImporter()
        let (session, _) = try make(.init(pairs: ["A1"]), importer: importer)
        session.toggleDarkroom()
        await session.sendToDarkroom(target: .photos)
        await session.sendToDarkroom(target: .photos)
        #expect(importer.calls.count == 1)

        session.toggleDarkroom()
        #expect(session.toast?.text == "RAW jest już w Zdjęciach")
        #expect(session.toast?.subtext?.hasPrefix("Album „") == true)
    }

    @Test func staleAssetAllowsSendingAgain() async throws {
        let importer = FakeImporter()
        let (session, folder) = try make(.init(pairs: ["A1"]), importer: importer)
        session.toggleDarkroom()
        await session.sendToDarkroom(target: .photos)
        importer.existing.removeAll()

        // Pressing C on a photo whose asset vanished releases it.
        session.toggleDarkroom()
        let item = try #require(session.photo(id: "A1"))
        #expect(!session.isInPhotos(item))
        #expect(session.isMarked(item))
        #expect(session.darkroomCount == 1)
        #expect(try SidecarStore().read(at: folder.appendingPathComponent("A1.xmp")).photosAssetID == nil)

        await session.sendToDarkroom(target: .photos)
        #expect(importer.calls.count == 2)
        #expect(session.isInPhotos(item))
    }

    @Test func staleAssetIsReimportedBySendWithoutPressingC() async throws {
        let importer = FakeImporter()
        let (session, _) = try make(.init(pairs: ["A1"]), importer: importer)
        session.toggleDarkroom()
        await session.sendToDarkroom(target: .photos)
        importer.existing.removeAll()
        await session.sendToDarkroom(target: .photos)
        #expect(importer.calls.count == 2)
    }

    @Test func authorizationFailureChangesNothing() async throws {
        let importer = FakeImporter()
        importer.error = .accessDenied
        let (session, folder) = try make(.init(pairs: ["A1"]), importer: importer)
        session.toggleDarkroom()
        await session.sendToDarkroom(target: .photos)

        let item = try #require(session.photo(id: "A1"))
        #expect(!session.isInPhotos(item))
        #expect(session.darkroomCount == 1)
        #expect(try SidecarStore().read(at: folder.appendingPathComponent("A1.xmp")).photosAssetID == nil)
        #expect(session.toast?.text == "Brak dostępu do Zdjęć")
        #expect(session.isSendingToDarkroom == false)
    }

    @Test func folderTargetStillMovesFilesAndNeverCallsImporter() async throws {
        let importer = FakeImporter()
        let (session, folder) = try make(.init(pairs: ["A1"]), importer: importer)
        session.toggleDarkroom()
        await session.sendToDarkroom(target: .folder)
        #expect(importer.calls.isEmpty)
        #expect(exists(folder, "Ciemnia/A1.ARW") && !exists(folder, "A1.ARW"))
    }

    @Test func sidecarStoreRoundTripsAssetIDAndClearsIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xmp")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SidecarStore()
        try store.write(SidecarState(photosAssetID: "ABC/L0/001"), to: url)
        #expect(try store.read(at: url).photosAssetID == "ABC/L0/001")
        try store.clearPhotoSiftFields(at: url)
        #expect(try store.read(at: url).photosAssetID == nil)
    }
}
