import Foundation
import Testing
import PhotoSiftTestSupport
@testable import PhotoSiftCore

@Suite("PhotoTrasherTests")
struct PhotoTrasherTests {
    private func item(_ id: String, in folder: FixtureFolder, jpeg: Bool, raw: Bool) -> PhotoItem {
        PhotoItem(
            id: id,
            jpegURL: jpeg ? folder.url.appendingPathComponent("\(id).JPG") : nil,
            rawURL: raw ? folder.url.appendingPathComponent("\(id).ARW") : nil,
            sidecarURL: folder.url.appendingPathComponent("\(id).xmp")
        )
    }

    private func exists(_ folder: FixtureFolder, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(name).path)
    }

    private func cleanUp(_ folder: FixtureFolder) {
        try? FileManager.default.trashItem(at: folder.url, resultingItemURL: nil)
    }

    @Test func trashesPairWithSidecarAndLeavesAlbumUntouched() throws {
        let folder = try FixtureFolder.make(.init(pairs: ["DSC01"], album: ["DSC01"]))
        defer { cleanUp(folder) }
        try Data("xmp".utf8).write(to: folder.url.appendingPathComponent("DSC01.xmp"))

        let result = PhotoTrasher().trash(item("DSC01", in: folder, jpeg: true, raw: true))

        #expect(result.isComplete)
        #expect(Set(result.trashed.map(\.lastPathComponent)) == ["DSC01.JPG", "DSC01.ARW", "DSC01.xmp"])
        #expect(!exists(folder, "DSC01.JPG"))
        #expect(!exists(folder, "DSC01.ARW"))
        #expect(!exists(folder, "DSC01.xmp"))
        #expect(exists(folder, "Album/DSC01.JPG"))
    }

    @Test func trashesJpegOnly() throws {
        let folder = try FixtureFolder.make(.init(jpegOnly: ["DSC02"]))
        defer { cleanUp(folder) }

        let result = PhotoTrasher().trash(item("DSC02", in: folder, jpeg: true, raw: false))

        #expect(result.isComplete)
        #expect(result.trashed.map(\.lastPathComponent) == ["DSC02.JPG"])
        #expect(!exists(folder, "DSC02.JPG"))
    }

    @Test func trashesRawOnly() throws {
        let folder = try FixtureFolder.make(.init(rawOnly: ["DSC03"]))
        defer { cleanUp(folder) }

        let result = PhotoTrasher().trash(item("DSC03", in: folder, jpeg: false, raw: true))

        #expect(result.isComplete)
        #expect(result.trashed.map(\.lastPathComponent) == ["DSC03.ARW"])
        #expect(!exists(folder, "DSC03.ARW"))
    }

    @Test func reportsFilesThatCouldNotBeTrashed() throws {
        let folder = try FixtureFolder.make(.init(pairs: ["DSC04"]))
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: folder.url.appendingPathComponent("DSC04.JPG").path)
            cleanUp(folder)
        }
        let jpeg = folder.url.appendingPathComponent("DSC04.JPG")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: jpeg.path)

        let result = PhotoTrasher().trash(item("DSC04", in: folder, jpeg: true, raw: true))

        #expect(result.failed.map(\.url.lastPathComponent) == ["DSC04.JPG"])
        #expect(result.trashed.map(\.lastPathComponent) == ["DSC04.ARW"])
        #expect(exists(folder, "DSC04.JPG"))
    }
}
