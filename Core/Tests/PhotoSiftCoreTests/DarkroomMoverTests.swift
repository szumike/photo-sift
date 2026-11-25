import CoreGraphics
import Foundation
import Testing
import PhotoSiftTestSupport
@testable import PhotoSiftCore

@Suite("DarkroomMoverTests")
struct DarkroomMoverTests {
    private let fileManager = FileManager.default

    private func item(_ id: String, in folder: URL, withRaw: Bool = true) -> PhotoItem {
        PhotoItem(
            id: id,
            jpegURL: folder.appendingPathComponent("\(id).JPG"),
            rawURL: withRaw ? folder.appendingPathComponent("\(id).ARW") : nil,
            sidecarURL: folder.appendingPathComponent("\(id).xmp")
        )
    }

    private func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }

    private func writeSidecar(for item: PhotoItem, foreignRating: Bool) throws {
        let store = SidecarStore()
        let edit = EditParams(
            crop: CGRect(x: 0, y: 0, width: 1, height: 1),
            orientation: .landscape, angle: 0, temperature: 10, tint: 0
        )
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: item.sidecarURL)
        if foreignRating {
            var text = try String(contentsOf: item.sidecarURL, encoding: .utf8)
            text = text.replacingOccurrences(
                of: "<rdf:Description ",
                with: "<rdf:Description xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmp:Rating=\"4\" "
            )
            try text.write(to: item.sidecarURL, atomically: true, encoding: .utf8)
        }
    }

    @Test func movesRawAndSidecarAndKeepsJpeg() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["DSC00001"]))
        let photo = item("DSC00001", in: fixture.url)
        try writeSidecar(for: photo, foreignRating: false)

        let report = DarkroomMover(sessionFolder: fixture.url).send([photo])

        let darkroom = fixture.url.appendingPathComponent("Ciemnia")
        #expect(report.moved == ["DSC00001"])
        #expect(report.conflicts.isEmpty && report.failures.isEmpty)
        #expect(exists(darkroom.appendingPathComponent("DSC00001.ARW")))
        #expect(!exists(photo.rawURL!))
        #expect(exists(photo.jpegURL!))
        // Only photosift fields were present, so the cleared sidecar disappears.
        #expect(!exists(photo.sidecarURL))
    }

    @Test func movedSidecarHasNoPhotoSiftFieldsButKeepsForeignOnes() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["DSC00001"]))
        let photo = item("DSC00001", in: fixture.url)
        try writeSidecar(for: photo, foreignRating: true)

        _ = DarkroomMover(sessionFolder: fixture.url).send([photo])

        let moved = fixture.url.appendingPathComponent("Ciemnia/DSC00001.xmp")
        #expect(!exists(photo.sidecarURL))
        let text = try String(contentsOf: moved, encoding: .utf8)
        #expect(text.contains("Rating"))
        #expect(!text.contains("photosift"))
        #expect(try SidecarStore().read(at: moved) == SidecarState())
    }

    @Test func movesRawWithoutSidecar() throws {
        let fixture = try FixtureFolder.make(.init(rawOnly: ["DSC00002"]))
        let photo = PhotoItem(
            id: "DSC00002",
            rawURL: fixture.url.appendingPathComponent("DSC00002.ARW"),
            sidecarURL: fixture.url.appendingPathComponent("DSC00002.xmp")
        )

        let report = DarkroomMover(sessionFolder: fixture.url).send([photo])

        #expect(report.moved == ["DSC00002"])
        #expect(exists(fixture.url.appendingPathComponent("Ciemnia/DSC00002.ARW")))
        #expect(!exists(fixture.url.appendingPathComponent("Ciemnia/DSC00002.xmp")))
    }

    @Test func createsDarkroomFolderWhenMissing() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["DSC00001"]))
        let darkroom = fixture.url.appendingPathComponent("Ciemnia")
        #expect(!exists(darkroom))

        _ = DarkroomMover(sessionFolder: fixture.url).send([item("DSC00001", in: fixture.url)])

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: darkroom.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func conflictSkipsPhotoWithoutOverwriting() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["DSC00001", "DSC00002"]))
        let darkroom = fixture.url.appendingPathComponent("Ciemnia", isDirectory: true)
        try fileManager.createDirectory(at: darkroom, withIntermediateDirectories: true)
        let existing = darkroom.appendingPathComponent("DSC00001.ARW")
        let marker = Data("existing".utf8)
        try marker.write(to: existing)
        let conflicting = item("DSC00001", in: fixture.url)
        let other = item("DSC00002", in: fixture.url)
        try writeSidecar(for: conflicting, foreignRating: false)

        let report = DarkroomMover(sessionFolder: fixture.url).send([conflicting, other])

        #expect(report.conflicts == ["DSC00001"])
        #expect(report.moved == ["DSC00002"])
        #expect(try Data(contentsOf: existing) == marker)
        #expect(exists(conflicting.rawURL!))
        #expect(try SidecarStore().read(at: conflicting.sidecarURL).markedForDarkroom)
    }

    @Test func sidecarConflictLeavesRawInPlace() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["DSC00001"]))
        let darkroom = fixture.url.appendingPathComponent("Ciemnia", isDirectory: true)
        try fileManager.createDirectory(at: darkroom, withIntermediateDirectories: true)
        let existing = darkroom.appendingPathComponent("DSC00001.xmp")
        try Data("existing".utf8).write(to: existing)
        let photo = item("DSC00001", in: fixture.url)
        try writeSidecar(for: photo, foreignRating: false)

        let report = DarkroomMover(sessionFolder: fixture.url).send([photo])

        #expect(report.conflicts == ["DSC00001"])
        #expect(exists(photo.rawURL!))
        #expect(exists(photo.sidecarURL))
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
    }

    @Test func reportsPhotoWithoutRaw() throws {
        let fixture = try FixtureFolder.make(.init(jpegOnly: ["DSC00003"]))
        let photo = item("DSC00003", in: fixture.url, withRaw: false)

        let report = DarkroomMover(sessionFolder: fixture.url).send([photo])

        #expect(report.withoutRaw == ["DSC00003"])
        #expect(report.moved.isEmpty)
        #expect(exists(photo.jpegURL!))
    }

    @Test func photoOutsideSessionFolderIsReportedAsFailureAndUntouched() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["DSC00001"]))
        let other = try FixtureFolder.make(.init(pairs: ["DSC00002"]))
        let foreign = item("DSC00002", in: other.url)
        let own = item("DSC00001", in: fixture.url)

        let report = DarkroomMover(sessionFolder: fixture.url).send([foreign, own])

        #expect(report.failures.map(\.id) == ["DSC00002"])
        #expect(report.moved == ["DSC00001"])
        #expect(exists(foreign.rawURL!))
        #expect(!exists(other.url.appendingPathComponent("Ciemnia")))
    }

    @Test func sidecarOutsideSessionFolderIsReportedAsFailure() throws {
        let fixture = try FixtureFolder.make(.init(pairs: ["DSC00001"]))
        let other = try FixtureFolder.make(.init())
        var photo = item("DSC00001", in: fixture.url)
        photo.sidecarURL = other.url.appendingPathComponent("DSC00001.xmp")

        let report = DarkroomMover(sessionFolder: fixture.url).send([photo])

        #expect(report.failures.map(\.id) == ["DSC00001"])
        #expect(report.moved.isEmpty)
        #expect(exists(photo.rawURL!))
    }
}
