import Foundation
import Testing
import PhotoSiftCore
import PhotoSiftTestSupport

@Suite struct FolderScannerTests {
    private func make(_ spec: FixtureFolder.Spec) throws -> FixtureFolder {
        try FixtureFolder.make(spec)
    }

    private func cleanup(_ folder: FixtureFolder) {
        try? FileManager.default.removeItem(at: folder.url)
    }

    @Test func pairsJpegAndRawIntoOneItem() throws {
        let folder = try make(.init(pairs: ["DSC00001"]))
        defer { cleanup(folder) }

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == "DSC00001")
        #expect(item.jpegURL?.lastPathComponent == "DSC00001.JPG")
        #expect(item.rawURL?.lastPathComponent == "DSC00001.ARW")
        #expect(item.sidecarURL == folder.url.appendingPathComponent("DSC00001.xmp"))
        #expect(item.isSentToDarkroom == false)
        #expect(item.captureDate != nil)
        #expect(item.isRawOnly == false)
    }

    @Test func jpegOnlyAndRawOnly() throws {
        let folder = try make(.init(jpegOnly: ["DSC00001"], rawOnly: ["DSC00002"]))
        defer { cleanup(folder) }

        let items = try FolderScanner.scan(folder: folder.url)

        let jpeg = try #require(items.first { $0.id == "DSC00001" })
        #expect(jpeg.jpegURL != nil && jpeg.rawURL == nil && !jpeg.isRawOnly)
        let raw = try #require(items.first { $0.id == "DSC00002" })
        #expect(raw.jpegURL == nil && raw.rawURL != nil && raw.isRawOnly)
        #expect(raw.captureDate != nil)
    }

    @Test func recognizesExtensionsCaseInsensitively() throws {
        let folder = try make(.init())
        defer { cleanup(folder) }
        for name in ["a.jpg", "b.JPEG", "c.Jpeg", "d.arw", "e.Arw", "f.PNG", "g.txt", "h.xmp"] {
            try Data("x".utf8).write(to: folder.url.appendingPathComponent(name))
        }

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.id) == ["a", "b", "c", "d", "e"])
        #expect(items.map { $0.jpegURL != nil } == [true, true, true, false, false])
    }

    @Test func pairsMixedCaseExtensions() throws {
        let folder = try make(.init())
        defer { cleanup(folder) }
        try Data("x".utf8).write(to: folder.url.appendingPathComponent("DSC1.jpeg"))
        try Data("x".utf8).write(to: folder.url.appendingPathComponent("DSC1.arw"))

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.count == 1)
        #expect(items.first?.jpegURL != nil && items.first?.rawURL != nil)
    }

    @Test func skipsSubfoldersAndOtherFiles() throws {
        let folder = try make(.init(pairs: ["DSC00001"], darkroom: ["DSC00002"], album: ["DSC00003"]))
        defer { cleanup(folder) }
        try Data("x".utf8).write(to: folder.url.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(
            at: folder.url.appendingPathComponent("Other.jpg", isDirectory: true),
            withIntermediateDirectories: true
        )

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.id) == ["DSC00001"])
    }

    @Test func marksPhotosWithRawInDarkroom() throws {
        let folder = try make(.init(pairs: ["DSC00001"], jpegOnly: ["DSC00002", "DSC00003"]))
        defer { cleanup(folder) }
        let darkroom = folder.url.appendingPathComponent("Ciemnia", isDirectory: true)
        try FileManager.default.createDirectory(at: darkroom, withIntermediateDirectories: true)
        // DSC00002: RAW already moved to Ciemnia/. DSC00003: only a JPEG in Ciemnia/ (does not count).
        try Data("x".utf8).write(to: darkroom.appendingPathComponent("DSC00002.ARW"))
        try Data("x".utf8).write(to: darkroom.appendingPathComponent("DSC00003.JPG"))

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.first { $0.id == "DSC00001" }?.isSentToDarkroom == false)
        let sent = try #require(items.first { $0.id == "DSC00002" })
        #expect(sent.isSentToDarkroom == true)
        #expect(sent.rawURL == nil)
        #expect(items.first { $0.id == "DSC00003" }?.isSentToDarkroom == false)
    }

    @Test func sortsByCaptureDateThenName() throws {
        // The fixture assigns increasing capture dates in creation order, so "B" is earlier than "A".
        let folder = try make(.init(pairs: ["DSC0B", "DSC0A"], jpegOnly: ["DSC0C"]))
        defer { cleanup(folder) }

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.id) == ["DSC0B", "DSC0A", "DSC0C"])
    }

    @Test func sortsPhotosWithoutDateLastByName() throws {
        let folder = try make(.init(jpegOnly: ["DSC0Z"]))
        defer { cleanup(folder) }
        for name in ["B.jpg", "A.jpg"] {
            try Data("x".utf8).write(to: folder.url.appendingPathComponent(name))
        }

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.id) == ["DSC0Z", "A", "B"])
        #expect(items.map { $0.captureDate != nil } == [true, false, false])
    }

    @Test func emptyFolderGivesNoItems() throws {
        let folder = try make(.init())
        defer { cleanup(folder) }

        #expect(try FolderScanner.scan(folder: folder.url).isEmpty)
    }
}
