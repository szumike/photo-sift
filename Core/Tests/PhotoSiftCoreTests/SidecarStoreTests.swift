import CoreGraphics
import Foundation
import Testing
@testable import PhotoSiftCore

@Suite("SidecarStoreTests")
struct SidecarStoreTests {
    let store = SidecarStore()

    private func makeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("DSC01234.xmp")
    }

    private let edit = EditParams(
        crop: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25),
        orientation: .portrait,
        angle: -3.25,
        temperature: 12.5,
        tint: -7,
        exposure: 0.75,
        highlights: -30,
        shadows: 45
    )

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private let foreignXMP = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """

    @Test func roundTripsEditAndMark() throws {
        let url = try makeURL()
        let state = SidecarState(edit: edit, markedForDarkroom: true)
        try store.write(state, to: url)
        #expect(try store.read(at: url) == state)
    }

    @Test func roundTripsEditWithoutMark() throws {
        let url = try makeURL()
        let state = SidecarState(edit: edit, markedForDarkroom: false)
        try store.write(state, to: url)
        #expect(try store.read(at: url) == state)
    }

    @Test func roundTripsMarkWithoutEdit() throws {
        let url = try makeURL()
        let state = SidecarState(edit: nil, markedForDarkroom: true)
        try store.write(state, to: url)
        #expect(try store.read(at: url) == state)
    }

    @Test func readsMissingFileAsEmptyState() throws {
        #expect(try store.read(at: makeURL()) == SidecarState())
    }

    @Test func emptyStateCreatesNoFile() throws {
        let url = try makeURL()
        try store.write(SidecarState(), to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func emptyStateRemovesFileWithOnlyPhotoSiftFields() throws {
        let url = try makeURL()
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: url)
        try store.write(SidecarState(), to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func overwriteReplacesPreviousFields() throws {
        let url = try makeURL()
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: url)
        try store.write(SidecarState(edit: nil, markedForDarkroom: true), to: url)
        #expect(try store.read(at: url) == SidecarState(edit: nil, markedForDarkroom: true))
    }

    @Test func preservesForeignFieldsOnWrite() throws {
        let url = try makeURL()
        try foreignXMP.write(to: url, atomically: true, encoding: .utf8)
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: url)
        #expect(try text(url).contains("Rating"))
        #expect(try store.read(at: url) == SidecarState(edit: edit, markedForDarkroom: true))
    }

    @Test func missingExposureFieldReadsAsZero() throws {
        let url = try makeURL()
        try store.write(SidecarState(edit: edit, markedForDarkroom: false), to: url)
        let legacy = try text(url)
            .components(separatedBy: "\n")
            .filter { !$0.contains("photosift:exposure") }
            .joined(separator: "\n")
        try legacy.write(to: url, atomically: true, encoding: .utf8)
        var expected = edit
        expected.exposure = 0
        #expect(try store.read(at: url).edit == expected)
    }

    @Test func missingHighlightsAndShadowsFieldsReadAsZero() throws {
        let url = try makeURL()
        try store.write(SidecarState(edit: edit, markedForDarkroom: false), to: url)
        let legacy = try text(url)
            .components(separatedBy: "\n")
            .filter { !$0.contains("photosift:highlights") && !$0.contains("photosift:shadows") }
            .joined(separator: "\n")
        try legacy.write(to: url, atomically: true, encoding: .utf8)
        var expected = edit
        expected.highlights = 0
        expected.shadows = 0
        #expect(try store.read(at: url).edit == expected)
    }

    @Test func writesHighlightsAndShadowsFields() throws {
        let url = try makeURL()
        try store.write(SidecarState(edit: edit, markedForDarkroom: false), to: url)
        let xmp = try text(url)
        #expect(xmp.contains("highlights") && xmp.contains("shadows"))
    }

    @Test func writesExposureField() throws {
        let url = try makeURL()
        try store.write(SidecarState(edit: edit, markedForDarkroom: false), to: url)
        #expect(try text(url).contains("exposure"))
    }

    @Test func emptyStateKeepsFileWithForeignFields() throws {
        let url = try makeURL()
        try foreignXMP.write(to: url, atomically: true, encoding: .utf8)
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: url)
        try store.write(SidecarState(), to: url)
        #expect(try text(url).contains("Rating"))
        #expect(try store.read(at: url) == SidecarState())
    }

    @Test func clearRemovesPhotoSiftFieldsAndKeepsOthers() throws {
        let url = try makeURL()
        try foreignXMP.write(to: url, atomically: true, encoding: .utf8)
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: url)
        try store.clearPhotoSiftFields(at: url)
        let content = try text(url)
        #expect(content.contains("Rating"))
        #expect(!content.contains("photosift"))
        #expect(try store.read(at: url) == SidecarState())
    }

    @Test func clearDeletesFileWithOnlyPhotoSiftFields() throws {
        let url = try makeURL()
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: url)
        try store.clearPhotoSiftFields(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func clearOnMissingFileDoesNothing() throws {
        let url = try makeURL()
        try store.clearPhotoSiftFields(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func writtenFileContainsNoCrsFields() throws {
        let url = try makeURL()
        try foreignXMP.write(to: url, atomically: true, encoding: .utf8)
        try store.write(SidecarState(edit: edit, markedForDarkroom: true), to: url)
        let content = try text(url)
        #expect(!content.contains("crs:"))
        #expect(content.contains("photosift:"))
    }

    @Test func garbageFileThrowsOnRead() throws {
        let url = try makeURL()
        try "not xmp".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: SidecarError.self) { try store.read(at: url) }
    }
}
