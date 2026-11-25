import Foundation
import Testing
import PhotoSiftTestSupport
@testable import PhotoSiftCore

@MainActor
@Suite("SessionUndoTests")
struct SessionUndoTests {
    private func make(_ spec: FixtureFolder.Spec) throws -> (Session, URL) {
        let fixture = try FixtureFolder.make(spec)
        return (try Session(folder: fixture.url), fixture.url)
    }

    private func xmp(_ folder: URL, _ id: String) throws -> SidecarState {
        try SidecarStore().read(at: folder.appendingPathComponent("\(id).xmp"))
    }

    private var temperature: (Session) -> Double? { { $0.currentEditParams?.temperature } }

    @Test func undoAndRedoOfSliderChange() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        #expect(!session.canUndo && !session.canRedo)
        session.updateEdit { $0.temperature = 30 }
        session.updateEdit { $0.temperature = 50 }
        #expect(session.canUndo && !session.canRedo)
        session.undoEdit()
        #expect(temperature(session) == 30)
        session.undoEdit()
        #expect(temperature(session) == 0)
        #expect(!session.canUndo && session.canRedo)
        session.redoEdit()
        session.redoEdit()
        #expect(temperature(session) == 50)
        #expect(!session.canRedo)
    }

    @Test func gestureWithManyUpdatesIsOneStep() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.beginEditGesture()
        for value in stride(from: 5.0, through: 50, by: 5) { session.updateEdit { $0.temperature = value } }
        #expect(!session.canUndo)
        session.endEditGesture()
        #expect(session.canUndo)
        session.undoEdit()
        #expect(temperature(session) == 0)
        #expect(!session.canUndo)
        session.redoEdit()
        #expect(temperature(session) == 50)
    }

    @Test func gestureIsNotTimeBased() async throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.beginEditGesture()
        session.updateEdit { $0.temperature = 10 }
        try await Task.sleep(for: .milliseconds(700))
        session.updateEdit { $0.temperature = 20 }
        session.endEditGesture()
        session.undoEdit()
        #expect(temperature(session) == 0)
        #expect(!session.canUndo)
    }

    @Test func updatesOutsideGesturesAreSeparateSteps() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.temperature = 10 }
        session.updateEdit { $0.temperature = 20 }
        session.undoEdit()
        #expect(temperature(session) == 10)
        session.undoEdit()
        #expect(temperature(session) == 0)
    }

    @Test func consecutiveGesturesAreSeparateSteps() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        for value in [10.0, 20] {
            session.beginEditGesture()
            session.updateEdit { $0.temperature = value - 5 }
            session.updateEdit { $0.temperature = value }
            session.endEditGesture()
        }
        session.undoEdit()
        #expect(temperature(session) == 10)
        session.undoEdit()
        #expect(temperature(session) == 0)
    }

    @Test func gestureWithoutChangeAddsNoStep() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.beginEditGesture()
        session.endEditGesture()
        #expect(!session.canUndo)
        session.beginEditGesture()
        session.updateEdit { $0.temperature = 10 }
        session.updateEdit { $0.temperature = 0 }
        session.endEditGesture()
        #expect(!session.canUndo)
    }

    @Test func undoDuringGestureEndsItFirst() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.beginEditGesture()
        session.updateEdit { $0.temperature = 10 }
        session.updateEdit { $0.temperature = 30 }
        session.undoEdit()
        #expect(temperature(session) == 0)
        session.updateEdit { $0.temperature = 5 }
        session.undoEdit()
        #expect(temperature(session) == 0)
    }

    @Test func changingPhotoEndsGesture() throws {
        let (session, _) = try make(.init(pairs: ["A1", "A2"]))
        session.beginEditGesture()
        session.updateEdit { $0.temperature = 10 }
        session.next()
        session.updateEdit { $0.temperature = 20 }
        session.undoEdit()
        #expect(temperature(session) == 0)
        session.previous()
        #expect(session.canUndo)
        session.undoEdit()
        #expect(temperature(session) == 0)
    }

    @Test func resetAndPasteDuringGestureAreOwnSteps() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.beginEditGesture()
        session.updateEdit { $0.temperature = 30 }
        session.resetEdit()
        session.undoEdit()
        #expect(temperature(session) == 30)
        session.undoEdit()
        #expect(temperature(session) == 0)
    }

    @Test func historiesAreSeparatePerPhoto() throws {
        let (session, _) = try make(.init(pairs: ["A1", "A2"]))
        session.updateEdit { $0.temperature = 10 }
        session.next()
        #expect(!session.canUndo)
        session.updateEdit { $0.temperature = 20 }
        session.undoEdit()
        #expect(temperature(session) == 0)
        session.previous()
        #expect(session.canUndo)
        #expect(temperature(session) == 10)
        session.undoEdit()
        #expect(temperature(session) == 0)
    }

    @Test func newEditClearsRedo() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.temperature = 10 }
        session.undoEdit()
        #expect(session.canRedo)
        session.updateEdit { $0.tint = 7 }
        #expect(!session.canRedo)
    }

    @Test func undoAfterPasteWhiteBalanceOnThreePhotos() throws {
        let (session, _) = try make(.init(pairs: ["A1", "A2", "A3"]))
        session.updateEdit { $0.temperature = 40; $0.tint = 4 }
        session.copyWhiteBalance()
        session.undoEdit()
        session.toggleView()
        session.selectAll()
        session.pasteWhiteBalance()
        for id in ["A1", "A2", "A3"] {
            #expect(session.state(of: id).edit?.temperature == 40)
        }
        for id in ["A1", "A2", "A3"] {
            session.select(id)
            session.undoEdit()
            #expect(session.state(of: id).edit == nil)
            #expect(session.canRedo)
        }
    }

    @Test func undoOfResetRestoresEdit() throws {
        let (session, _) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.temperature = 30 }
        session.resetEdit()
        #expect(!session.isEdited(session.currentPhoto!))
        session.undoEdit()
        #expect(temperature(session) == 30)
        session.redoEdit()
        #expect(!session.isEdited(session.currentPhoto!))
    }

    @Test func undoBackToIdentityRemovesXMPEdit() throws {
        let (session, folder) = try make(.init(pairs: ["A1"]))
        session.updateEdit { $0.temperature = 30 }
        session.flushPendingSaves()
        #expect(try xmp(folder, "A1").edit?.temperature == 30)
        session.undoEdit()
        session.flushPendingSaves()
        #expect(try xmp(folder, "A1").edit == nil)
        #expect(!session.isEdited(session.currentPhoto!))
        session.redoEdit()
        session.flushPendingSaves()
        #expect(try xmp(folder, "A1").edit?.temperature == 30)
    }

    @Test func undoIsNoOpOnLockedPhoto() throws {
        let (session, _) = try make(.init(pairs: ["A1"], rawOnly: ["R1"]))
        session.updateEdit { $0.temperature = 30 }
        session.toggleDarkroom()
        #expect(session.isEditLocked(session.currentPhoto!))
        #expect(!session.canUndo)
        session.undoEdit()
        #expect(temperature(session) == 30)
        session.toggleDarkroom()
        session.undoEdit()
        #expect(temperature(session) == 0)
    }
}
