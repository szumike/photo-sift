import Foundation
import Observation
import Testing
import PhotoSiftTestSupport
@testable import PhotoSiftCore

@MainActor
@Suite("SessionEditTests")
struct SessionEditTests {
    private let fileManager = FileManager.default

    private func make(_ spec: FixtureFolder.Spec, saveDelay: Duration = .milliseconds(300)) throws -> (Session, URL) {
        let fixture = try FixtureFolder.make(spec)
        return (try Session(folder: fixture.url, saveDelay: saveDelay), fixture.url)
    }

    private func xmp(_ folder: URL, _ id: String) throws -> SidecarState {
        try SidecarStore().read(at: folder.appendingPathComponent("\(id).xmp"))
    }

    @Test func updateEditSavesToXMPAfterDelay() async throws {
        let (session, folder) = try make(.init(pairs: ["A1"]), saveDelay: .milliseconds(50))
        #expect(session.updateEdit { $0.temperature = 30 })
        #expect(!session.isSaved)
        #expect(!fileManager.fileExists(atPath: folder.appendingPathComponent("A1.xmp").path))
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.isSaved)
        #expect(try xmp(folder, "A1").edit?.temperature == 30)
        #expect(session.isEdited(session.currentPhoto!))
    }

    @Test func isSavedIsObservableAndFlipsAfterDebounce() async throws {
        let (session, _) = try make(.init(pairs: ["A1"]), saveDelay: .milliseconds(50))
        #expect(session.updateEdit { $0.temperature = 30 })
        let changed = Task { @MainActor in
            await withCheckedContinuation { continuation in
                withObservationTracking { _ = session.isSaved } onChange: { continuation.resume() }
            }
        }
        #expect(!session.isSaved)
        await changed.value
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.isSaved)
    }

    @Test func flushWritesImmediatelyAndRepeatedChangesCollapse() throws {
        let (session, folder) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.temperature = 10 }
        session.updateEdit { $0.tint = -5 }
        session.flushPendingSaves()
        let edit = try xmp(folder, "A1").edit
        #expect(edit?.temperature == 10 && edit?.tint == -5)
    }

    @Test func identityEditCountsAsNoEdit() throws {
        let (session, folder) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.temperature = 10 }
        session.updateEdit { $0.temperature = 0 }
        session.flushPendingSaves()
        #expect(!session.isEdited(session.currentPhoto!))
        #expect(!fileManager.fileExists(atPath: folder.appendingPathComponent("A1.xmp").path))
    }

    @Test func orientationFollowsImageShape() throws {
        // Fixture index 0 is landscape, index 1 portrait.
        let (session, _) = try make(.init(jpegOnly: ["A1", "A2"]))
        session.updateEdit { $0.temperature = 1 }
        #expect(session.currentEditParams?.orientation == .landscape)
        session.next()
        session.updateEdit { $0.temperature = 1 }
        #expect(session.currentEditParams?.orientation == .portrait)
    }

    @Test func editLockedForDarkroomAndRawOnly() throws {
        let (session, folder) = try make(.init(pairs: ["A1", "A2"], rawOnly: ["A3"]))
        session.toggleDarkroom()
        #expect(!session.updateEdit { $0.temperature = 10 })
        #expect(session.toast?.text == "Tego zdjęcia nie edytujesz w Photo Sift")
        #expect(try xmp(folder, "A1").edit == nil)

        session.next(); session.next()
        #expect(session.currentID == "A3")
        #expect(!session.updateEdit { $0.temperature = 10 })
        #expect(session.toast?.text == "Tego zdjęcia nie edytujesz w Photo Sift")

        session.previous()
        #expect(session.updateEdit { $0.temperature = 10 })
    }

    @Test func unmarkingDarkroomUnlocksEdit() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.toggleDarkroom()
        #expect(!session.updateEdit { $0.tint = 5 })
        session.toggleDarkroom()
        #expect(session.updateEdit { $0.tint = 5 })
    }

    @Test func resetClearsEditAndSidecar() throws {
        let (session, folder) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.temperature = 40 }
        session.flushPendingSaves()
        session.resetEdit()
        #expect(session.currentEditParams?.isIdentity == true)
        #expect(!fileManager.fileExists(atPath: folder.appendingPathComponent("A1.xmp").path))
        #expect(session.toast?.text == "Edycja zresetowana")
    }

    @Test func copyAndPasteWhiteBalanceSkipsLocked() throws {
        let (session, folder) = try make(.init(pairs: ["A1", "A2", "A3", "A4"]))
        session.updateEdit { $0.temperature = 25; $0.tint = -10 }
        session.copyWhiteBalance()
        #expect(session.toast?.text == "Skopiowano balans bieli")
        #expect(session.toast?.subtext == "Temp. 25 · Tint -10")

        session.next()
        session.next()                                     // A3
        session.toggleDarkroom()             // A3 locked
        session.toggleView()
        session.select("A2")
        session.select("A3", modifiers: .command)
        session.select("A4", modifiers: .command)
        session.pasteWhiteBalance()
        #expect(session.toast?.text == "Wklejono balans bieli: 2 zdjęcia")
        #expect(session.toast?.subtext == "Pominięto 1 (Ciemnia lub tylko RAW)")
        #expect(try xmp(folder, "A2").edit?.temperature == 25)
        #expect(try xmp(folder, "A4").edit?.tint == -10)
        #expect(try xmp(folder, "A3").edit == nil)
        #expect(session.isEdited(session.photo(id: "A2")!))
    }

    @Test func pasteWithoutClipboardShowsMessage() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.pasteWhiteBalance()
        #expect(session.toast?.text == "Najpierw skopiuj balans bieli")
    }

    @Test func editedFilterListsOnlyEdited() throws {
        let (session, _) = try make(.init(pairs: ["A1", "A2"]))
        session.next()
        session.updateEdit { $0.temperature = 5 }
        session.setFilter(.edited)
        #expect(session.visiblePhotos.map(\.id) == ["A2"])
        session.resetEdit()
        session.setFilter(.edited)
        #expect(session.visiblePhotos.isEmpty)
    }

    @Test func editsReloadFromXMPOnNewSession() throws {
        let (session, folder) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.angle = 3 }
        session.flushPendingSaves()
        let reopened = try Session(folder: folder)
        #expect(reopened.currentEditParams?.angle == 3)
        #expect(reopened.visiblePhotos.count == 1)
        reopened.setFilter(.edited)
        #expect(reopened.visiblePhotos.count == 1)
    }

    @Test func enterAndExitEditMode() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.enterEdit(tool: .crop)
        #expect(session.mode == .edit && session.tool == .crop)
        session.exitEdit()
        #expect(session.mode == .browse)
    }
}
