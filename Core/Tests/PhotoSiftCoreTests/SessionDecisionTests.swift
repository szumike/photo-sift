import Foundation
import Testing
import PhotoSiftTestSupport
@testable import PhotoSiftCore

@MainActor
@Suite("SessionDecisionTests")
struct SessionDecisionTests {
    private let fileManager = FileManager.default

    private func make(_ spec: FixtureFolder.Spec) throws -> (Session, URL) {
        let fixture = try FixtureFolder.make(spec)
        return (try Session(folder: fixture.url), fixture.url)
    }

    private func exists(_ folder: URL, _ name: String) -> Bool {
        fileManager.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    @Test func deleteTrashesFilesAndAdvances() throws {
        let (session, folder) = try make(.init(pairs: ["A1", "A2"]))
        session.delete()
        #expect(!exists(folder, "A1.JPG") && !exists(folder, "A1.ARW"))
        #expect(session.photos.map(\.id) == ["A2"])
        #expect(session.currentID == "A2")
        #expect(session.deletedCount == 1)
        #expect(session.toast?.text == "A1 w Koszu")
        #expect(session.toast?.subtext == "JPEG i ARW · przywrócisz w Finderze")
    }

    @Test func deleteLastPhotoSelectsPrevious() throws {
        let (session, _) = try make(.init(jpegOnly: ["A1", "A2"]))
        session.next()
        session.delete()
        #expect(session.currentID == "A1")
        #expect(session.toast?.subtext == "JPEG · przywrócisz w Finderze")
    }

    @Test func deleteSelectedInGridRemovesAll() throws {
        let (session, folder) = try make(.init(pairs: ["A1", "A2", "A3", "A4"]))
        session.toggleView()
        session.select("A1")
        session.select("A2", modifiers: .command)
        session.select("A3", modifiers: .command)
        session.delete()
        #expect(session.photos.map(\.id) == ["A4"])
        #expect(!exists(folder, "A2.JPG") && exists(folder, "A4.JPG"))
        #expect(session.deletedCount == 3)
        #expect(session.currentID == "A4")
        #expect(session.toast?.text == "3 zdjęcia w Koszu")
    }

    @Test func darkroomToggleMarksWithoutAdvancing() throws {
        let (session, folder) = try make(.init(pairs: ["A1", "A2"]))
        session.toggleDarkroom()
        #expect(session.isMarked(session.photo(id: "A1")!))
        #expect(session.currentID == "A1")
        #expect(session.toast?.text == "A1 → Ciemnia")
        #expect(session.darkroomCount == 1)
        #expect(try SidecarStore().read(at: folder.appendingPathComponent("A1.xmp")).markedForDarkroom)

        session.toggleDarkroom()
        #expect(!session.isMarked(session.photo(id: "A1")!))
        #expect(session.toast?.text == "A1: bez Ciemni")
        #expect(session.currentID == "A1")
        #expect(session.darkroomCount == 0)
        #expect(!exists(folder, "A1.xmp"))
    }

    @Test func darkroomOnJpegOnlyShowsMessageWithoutChange() throws {
        let (session, _) = try make(.init(jpegOnly: ["A1", "A2"]))
        session.toggleDarkroom()
        #expect(session.toast?.text == "Brak pliku RAW — nie można wysłać do Ciemni")
        #expect(session.currentID == "A1")
        #expect(session.darkroomCount == 0)
    }

    @Test func darkroomOnAlreadySentShowsMessage() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["A2"]))
        let darkroom = fixture.url.appendingPathComponent("Ciemnia", isDirectory: true)
        try fileManager.createDirectory(at: darkroom, withIntermediateDirectories: true)
        try fileManager.moveItem(
            at: fixture.url.appendingPathComponent("A2.ARW"), to: darkroom.appendingPathComponent("A2.ARW")
        )
        let session = try Session(folder: fixture.url)
        session.toggleDarkroom()
        #expect(session.toast?.text == "RAW jest już w Ciemnia/")
        #expect(session.toast?.subtext == "Cofniesz to, przenosząc A2.ARW w Finderze.")
        #expect(session.darkroomCount == 0)
        #expect(session.state(of: "A2") == SidecarState())
    }

    @Test func darkroomOnGridSelectionMarksAll() throws {
        let (session, _) = try make(.init(pairs: ["A1", "A2"], jpegOnly: ["A3"]))
        session.toggleView()
        session.selectAll()
        session.toggleDarkroom()
        #expect(session.darkroomCount == 2)
        #expect(session.toast?.text == "2 zdjęcia → Ciemnia")
        #expect(session.toast?.subtext == "Pominięto 1 (brak RAW lub już w Ciemnia/)")
        session.toggleDarkroom()
        #expect(session.darkroomCount == 0)
    }

    @Test func countersTrackExportAndDeletion() throws {
        let (session, _) = try make(.init(pairs: ["A1", "A2"], jpegOnly: ["A3"]))
        #expect(session.exportCount == 3)
        session.toggleDarkroom()
        #expect(session.exportCount == 2)
        session.next()
        session.delete()
        #expect(session.exportCount == 1)
        #expect(session.deletedCount == 1)
    }

    @Test func sendToDarkroomMovesMarkedRaws() async throws {
        let (session, folder) = try make(.init(pairs: ["A1", "A2"]))
        session.toggleDarkroom()
        await session.sendToDarkroom()
        #expect(exists(folder, "Ciemnia/A1.ARW"))
        #expect(exists(folder, "A1.JPG"))
        #expect(!exists(folder, "A1.ARW"))
        #expect(session.photo(id: "A1")?.isSentToDarkroom == true)
        #expect(session.darkroomCount == 0)
        #expect(session.toast?.text == "Przeniesiono 1 plik RAW do Ciemnia/")
        #expect(session.toast?.subtext == "JPEG-i zostały na miejscu.")
        #expect(session.exportCount == 1)
    }

    @Test func exportCopiesAndCountDropsToZero() async throws {
        let (session, folder) = try make(.init(pairs: ["A1"], jpegOnly: ["A2"]))
        let plan = session.exportPlan()
        #expect(plan.pendingCount == 2)
        let summary = await session.runExport(plan: plan)
        #expect(summary.copied == 2)
        #expect(exists(folder, "Album/A1.JPG"))
        #expect(session.exportCount == 0)
        #expect(!session.isExporting)
    }

    @Test func cancelledExportReportsProgress() async throws {
        let (session, _) = try make(.init(pairs: ["A1", "A2", "A3"]))
        let plan = session.exportPlan()
        let task = Task { await session.runExport(plan: plan) }
        task.cancel()
        let summary = await task.value
        #expect(summary.wasCancelled)
        #expect(session.toast?.text == "Eksport zatrzymany")
        #expect(session.toast?.subtext == "Zapisano \(summary.copied + summary.rendered) z 3.")
    }

    @Test func polishPlurals() {
        #expect(PolishPlural.photos(1) == "1 zdjęcie")
        #expect(PolishPlural.photos(3) == "3 zdjęcia")
        #expect(PolishPlural.photos(5) == "5 zdjęć")
        #expect(PolishPlural.photos(12) == "12 zdjęć")
        #expect(PolishPlural.photos(22) == "22 zdjęcia")
        #expect(PolishPlural.rawFiles(2) == "2 pliki RAW")
        #expect(PolishPlural.rawFiles(7) == "7 plików RAW")
        #expect(PolishPlural.list(["JPEG", "ARW", "XMP"]) == "JPEG, ARW i XMP")
    }

    @Test func partialTrashFailureDropsTrashedFilesFromPhoto() throws {
        let (session, folder) = try make(.init(pairs: ["A1", "A2"]))
        let raw = folder.appendingPathComponent("A1.ARW")
        try fileManager.setAttributes([.immutable: true], ofItemAtPath: raw.path)
        defer { try? fileManager.setAttributes([.immutable: false], ofItemAtPath: raw.path) }

        session.delete()

        #expect(!exists(folder, "A1.JPG"))
        #expect(exists(folder, "A1.ARW"))
        let item = try #require(session.photo(id: "A1"))
        #expect(item.jpegURL == nil)
        #expect(item.rawURL?.lastPathComponent == "A1.ARW")
        #expect(session.deletedCount == 0)
        #expect(session.toast?.text == "Nie przeniesiono do Kosza: 1 zdjęcie")
    }

    @Test func exportStatusesAreRefreshedWithTheCount() async throws {
        let (session, _) = try make(.init(pairs: ["A1"], jpegOnly: ["A2"], rawOnly: ["A3"]))
        #expect(session.exportStatuses == ["A1": .notExported, "A2": .notExported, "A3": .skipped(.rawOnly)])
        session.toggleDarkroom()
        #expect(session.exportStatuses["A1"] == .skipped(.darkroom))
        session.toggleDarkroom()
        await session.runExport(plan: session.exportPlan())
        #expect(session.exportStatuses["A1"] == .current)
        #expect(session.exportStatuses["A2"] == .current)
        #expect(session.exportCount == 0)
    }
}
