import Foundation
import Testing
import PhotoSiftTestSupport
@testable import PhotoSiftCore

@MainActor
@Suite("SessionNavigationTests")
struct SessionNavigationTests {
    private func session(
        _ spec: FixtureFolder.Spec = .init(pairs: ["A1", "A2", "A3"]),
        resumeID: String? = nil
    ) throws -> Session {
        try Session(folder: FixtureFolder.make(spec).url, resumeID: resumeID)
    }

    @Test func startsOnFirstPhotoInOrder() throws {
        let session = try session()
        #expect(session.visiblePhotos.map(\.id) == ["A1", "A2", "A3"])
        #expect(session.currentID == "A1")
        #expect(session.currentPosition == 1)
    }

    @Test func nextOnLastPhotoStaysOnIt() throws {
        let session = try session()
        session.next()
        session.next()
        #expect(session.currentID == "A3")
        session.next()
        #expect(session.currentID == "A3")
    }

    @Test func previousSteps() throws {
        let session = try session()
        session.next(); session.next(); session.next()
        #expect(session.currentID == "A3")
        session.previous()
        #expect(session.currentID == "A2")
        session.previous(); session.previous()
        #expect(session.currentID == "A1")
    }

    @Test func resumeStartsOnGivenPhotoWithToast() throws {
        let session = try session(resumeID: "A2")
        #expect(session.currentID == "A2")
        #expect(session.toast?.text == "Wznowiono od zdjęcia 2 z 3")
        let unknown = try self.session(resumeID: "nope")
        #expect(unknown.currentID == "A1")
        #expect(unknown.toast == nil)
    }

    @Test func filtersShowDarkroomAndEdited() throws {
        let session = try session(.init(pairs: ["A1", "A2", "A3"]))
        session.next()
        session.toggleDarkroom()          // A2 marked
        session.next()
        session.updateEdit { $0.temperature = 20 }       // A3 edited
        session.setFilter(.darkroom)
        #expect(session.visiblePhotos.map(\.id) == ["A2"])
        #expect(session.currentID == "A2")
        session.setFilter(.edited)
        #expect(session.visiblePhotos.map(\.id) == ["A3"])
        #expect(session.currentID == "A3")
        session.setFilter(.all)
        #expect(session.visiblePhotos.count == 3)
        #expect(session.currentID == "A3")
    }

    @Test func emptyFilterLeavesNoCurrent() throws {
        let session = try session()
        session.setFilter(.edited)
        #expect(session.visiblePhotos.isEmpty)
        #expect(session.currentID == nil)
    }

    @Test func toggleViewSwitchesAndKeepsCurrent() throws {
        let session = try session()
        session.next()
        session.toggleView()
        #expect(session.viewMode == .grid)
        session.toggleView()
        #expect(session.viewMode == .single)
        #expect(session.currentID == "A2")
        session.toggleView()
        session.openInSingle("A3")
        #expect(session.viewMode == .single)
        #expect(session.currentID == "A3")
    }

    @Test func multiSelectionOnlyInGrid() throws {
        let session = try session(.init(pairs: ["A1", "A2", "A3", "A4"]))
        session.select("A3", modifiers: .command)
        #expect(session.selection == ["A3"])
        #expect(session.currentID == "A3")
        session.selectAll()
        #expect(session.selection == ["A3"])

        session.toggleView()
        session.select("A1")
        session.select("A3", modifiers: .command)
        #expect(session.selection == ["A1", "A3"])
        session.select("A3", modifiers: .command)
        #expect(session.selection == ["A1"])
        session.select("A2")
        session.select("A4", modifiers: .shift)
        #expect(session.selection == ["A2", "A3", "A4"])
        session.clearSelection()
        #expect(session.selection.isEmpty)
        session.selectAll()
        #expect(session.selection.count == 4)
    }

    @Test func moveCurrentClampsInGrid() throws {
        let session = try session()
        session.toggleView()
        session.moveCurrent(by: 2)
        #expect(session.currentID == "A3")
        session.moveCurrent(by: 5)
        #expect(session.currentID == "A3")
        session.moveCurrent(by: -9)
        #expect(session.currentID == "A1")
    }
}
