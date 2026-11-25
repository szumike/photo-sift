import CoreGraphics
import Foundation
import ImageIO
import PhotoSiftTestSupport
import Testing

@testable import PhotoSiftCore

@Suite struct AlbumExporterTests {
    private let edit = EditParams(
        crop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), orientation: .landscape, temperature: 20
    )

    /// Photos: A (edited-capable pair), B (pair), C (JPEG only), D (RAW only).
    private struct Setup {
        let folder: FixtureFolder
        let items: [PhotoItem]
        var states: [String: SidecarState] = [:]
        let exporter: AlbumExporter
        var album: URL { folder.url.appendingPathComponent("Album") }

        func plan() -> ExportPlan { exporter.plan(items: items, states: states) }
        func status(_ id: String) -> ExportStatus? { plan().entries.first { $0.item.id == id }?.status }
        func albumFile(_ id: String) -> URL { album.appendingPathComponent("\(id).JPG") }
    }

    private func makeSetup(album: [String] = []) throws -> Setup {
        let folder = try FixtureFolder.make(.init(
            pairs: ["A", "B"], jpegOnly: ["C"], rawOnly: ["D"], album: album
        ))
        let items = try FolderScanner.scan(folder: folder.url)
        return Setup(folder: folder, items: items, exporter: AlbumExporter(sessionFolder: folder.url))
    }

    private func export(_ setup: Setup) async -> ExportSummary {
        await setup.exporter.run(plan: setup.plan())
    }

    private func albumFiles(_ setup: Setup) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: setup.album.path).sorted()
    }

    private func modificationDate(_ url: URL) throws -> Date {
        try #require(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    @Test func firstExportCopiesUneditedByteForByte() async throws {
        let setup = try makeSetup()
        #expect(setup.plan().newCount == 3)
        let summary = await export(setup)
        #expect(summary.copied == 3)
        #expect(summary.failed.isEmpty)
        for id in ["A", "B", "C"] {
            let original = setup.folder.url.appendingPathComponent("\(id).JPG")
            #expect(FileManager.default.contentsEqual(atPath: original.path, andPath: setup.albumFile(id).path))
        }
        #expect(setup.status("A") == .current)
    }

    @Test func editedPhotoIsRenderedWithCropSizeAndExif() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: edit)
        let summary = await export(setup)
        #expect(summary.rendered == 1)
        #expect(summary.copied == 2)

        let source = try #require(CGImageSourceCreateWithURL(setup.albumFile("A") as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 300)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 200)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] == [400])
        #expect(exif[kCGImagePropertyExifFNumber] as? Double == 2.8)
        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7M3")
        #expect(setup.status("A") == .current)
    }

    @Test func darkroomAndRawOnlyAreSkipped() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(markedForDarkroom: true)
        var items = setup.items
        let sentIndex = try #require(items.firstIndex { $0.id == "B" })
        items[sentIndex].isSentToDarkroom = true
        let plan = setup.exporter.plan(items: items, states: setup.states)
        #expect(plan.entries.first { $0.item.id == "A" }?.status == .skipped(.darkroom))
        #expect(plan.entries.first { $0.item.id == "B" }?.status == .skipped(.darkroom))
        #expect(plan.entries.first { $0.item.id == "D" }?.status == .skipped(.rawOnly))

        let summary = await setup.exporter.run(plan: plan)
        #expect(summary.copied == 1)
        #expect(try albumFiles(setup) == ["C.JPG"])
    }

    @Test func reExportWithoutChangesWritesNothing() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: edit)
        _ = await export(setup)
        let before = try ["A", "B", "C"].map { try modificationDate(setup.albumFile($0)) }

        let plan = setup.plan()
        #expect(plan.pendingCount == 0)
        let summary = await setup.exporter.run(plan: plan)
        #expect(summary == ExportSummary())
        let after = try ["A", "B", "C"].map { try modificationDate(setup.albumFile($0)) }
        #expect(before == after)
    }

    @Test func changedEditIsChangedThenCurrentAfterExport() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: edit)
        _ = await export(setup)

        var newEdit = edit
        newEdit.temperature = -40
        setup.states["A"] = SidecarState(edit: newEdit)
        #expect(setup.status("A") == .changed)
        let summary = await export(setup)
        #expect(summary.rendered == 1)
        #expect(setup.status("A") == .current)
    }

    @Test func editingAnUneditedExportMakesItChanged() async throws {
        var setup = try makeSetup()
        _ = await export(setup)
        setup.states["B"] = SidecarState(edit: edit)
        #expect(setup.status("B") == .changed)
        _ = await export(setup)
        #expect(setup.status("B") == .current)
    }

    @Test func resettingEditRestoresByteIdenticalCopy() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: edit)
        _ = await export(setup)

        setup.states["A"] = SidecarState(edit: nil)
        #expect(setup.status("A") == .changed)
        let summary = await export(setup)
        #expect(summary.copied == 1)
        let original = setup.folder.url.appendingPathComponent("A.JPG")
        #expect(FileManager.default.contentsEqual(atPath: original.path, andPath: setup.albumFile("A").path))
        #expect(setup.status("A") == .current)
    }

    @Test func identityEditCountsAsNoEdit() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: .identity(for: CGSize(width: 600, height: 400)))
        let summary = await export(setup)
        #expect(summary.rendered == 0)
        #expect(summary.copied == 3)
    }

    @Test func foreignFileIsConflictAndUntouched() async throws {
        var setup = try makeSetup(album: ["B"])
        let foreign = setup.albumFile("B")
        let foreignBytes = try Data(contentsOf: foreign)
        #expect(setup.status("B") == .conflict)

        setup.states["B"] = SidecarState(edit: edit)
        #expect(setup.status("B") == .conflict)
        let summary = await export(setup)
        #expect(summary.copied == 2)
        #expect(summary.rendered == 0)
        #expect(try Data(contentsOf: foreign) == foreignBytes)
        #expect(setup.status("B") == .conflict)
    }

    @Test func fileAppearingAfterPlanningIsNotOverwritten() async throws {
        let setup = try makeSetup()
        let plan = setup.plan()
        try FileManager.default.createDirectory(at: setup.album, withIntermediateDirectories: true)
        let foreignBytes = Data("not ours".utf8)
        try foreignBytes.write(to: setup.albumFile("C"))

        let summary = await setup.exporter.run(plan: plan)
        #expect(summary.copied == 2)
        #expect(try Data(contentsOf: setup.albumFile("C")) == foreignBytes)
    }

    @Test func unrelatedAlbumFileIsUntouched() async throws {
        let setup = try makeSetup(album: ["ZZ"])
        let unrelated = setup.albumFile("ZZ")
        let bytes = try Data(contentsOf: unrelated)
        _ = await export(setup)
        #expect(try Data(contentsOf: unrelated) == bytes)
        #expect(try albumFiles(setup).contains("ZZ.JPG"))
    }

    @Test func albumContainsOnlyJPEGsAfterExport() async throws {
        var setup = try makeSetup(album: ["ZZ"])
        setup.states["A"] = SidecarState(edit: edit)
        _ = await export(setup)
        setup.states["A"] = SidecarState(edit: EditParams(crop: edit.crop, orientation: .landscape, angle: 3))
        _ = await export(setup)
        let files = try albumFiles(setup)
        #expect(files == ["A.JPG", "B.JPG", "C.JPG", "ZZ.JPG"])
        #expect(files.allSatisfy { $0.hasSuffix(".jpg") || $0.hasSuffix(".JPG") })
    }

    @Test func cancellationStopsBeforeWriting() async throws {
        let setup = try makeSetup()
        let plan = setup.plan()
        let task = Task { () -> ExportSummary in
            withUnsafeCurrentTask { $0?.cancel() }
            return await setup.exporter.run(plan: plan)
        }
        let summary = await task.value
        #expect(summary.wasCancelled)
        #expect(summary.copied == 0)
    }

    // MARK: Ownership cache

    @Test func secondPlanDoesNotRereadUnchangedFiles() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: edit)
        _ = await export(setup)

        _ = setup.plan()
        let afterFirstPlan = setup.exporter.cache.evaluationCount
        #expect(afterFirstPlan == 3)
        let second = setup.plan()
        #expect(setup.exporter.cache.evaluationCount == afterFirstPlan)
        #expect(second.pendingCount == 0)
    }

    @Test func changedAlbumFileIsReevaluated() async throws {
        let setup = try makeSetup()
        _ = await export(setup)
        _ = setup.plan()
        let before = setup.exporter.cache.evaluationCount
        #expect(setup.status("B") == .current)

        let file = setup.albumFile("B")
        try Data("someone else's picture".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path
        )
        #expect(setup.status("B") == .conflict)
        #expect(setup.exporter.cache.evaluationCount == before + 1)
        #expect(setup.status("A") == .current)
        #expect(setup.exporter.cache.evaluationCount == before + 1)
    }

    @Test func exportInvalidatesCacheEntryOfWrittenFile() async throws {
        var setup = try makeSetup()
        _ = await export(setup)
        #expect(setup.status("A") == .current)
        setup.states["A"] = SidecarState(edit: edit)
        #expect(setup.status("A") == .changed)
        _ = await export(setup)
        #expect(setup.status("A") == .current)
    }

    // MARK: Temporary files

    private func hiddenFiles(_ setup: Setup) throws -> [String] {
        guard FileManager.default.fileExists(atPath: setup.album.path) else { return [] }
        return try albumFiles(setup).filter { $0.hasPrefix(".") }
    }

    @Test func failedExportLeavesNoHiddenFilesInAlbum() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: edit)
        let plan = setup.plan()
        try FileManager.default.removeItem(at: setup.folder.url.appendingPathComponent("A.JPG"))
        try FileManager.default.removeItem(at: setup.folder.url.appendingPathComponent("C.JPG"))

        let summary = await setup.exporter.run(plan: plan)
        #expect(Set(summary.failed) == ["A", "C"])
        #expect(summary.copied == 1)
        #expect(try hiddenFiles(setup).isEmpty)
        #expect(try albumFiles(setup) == ["B.JPG"])
    }

    @Test func cancelledExportLeavesNoHiddenFilesInAlbum() async throws {
        let setup = try makeSetup()
        let plan = setup.plan()
        let task = Task { () -> ExportSummary in
            withUnsafeCurrentTask { $0?.cancel() }
            return await setup.exporter.run(plan: plan)
        }
        _ = await task.value
        #expect(try hiddenFiles(setup).isEmpty)
    }

    @Test func successfulExportLeavesNoHiddenFilesInAlbum() async throws {
        var setup = try makeSetup()
        setup.states["A"] = SidecarState(edit: edit)
        _ = await export(setup)
        setup.states["A"] = SidecarState(edit: EditParams(crop: edit.crop, orientation: .landscape, angle: 3))
        _ = await export(setup)
        #expect(try hiddenFiles(setup).isEmpty)
    }

    // MARK: Orientation and GPS

    @Test func renderedPhotoWithOrientationKeepsMetadataAndResetsOrientation() async throws {
        // Stored 600x400 with orientation 6: displayed as 400x600.
        let folder = try FixtureFolder.make(.init(jpegOnly: ["R"], orientation: 6, includeGPS: true))
        let items = try FolderScanner.scan(folder: folder.url)
        let exporter = AlbumExporter(sessionFolder: folder.url)
        let rotated = EditParams(
            crop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), orientation: .portrait, temperature: 20
        )
        let plan = exporter.plan(items: items, states: ["R": SidecarState(edit: rotated)])
        let summary = await exporter.run(plan: plan)
        #expect(summary.rendered == 1)

        let output = folder.url.appendingPathComponent("Album/R.JPG")
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 300)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect((tiff[kCGImagePropertyTIFFOrientation] as? Int ?? 1) == 1)
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7M3")
        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifPixelXDimension] as? Int == 200)
        #expect(exif[kCGImagePropertyExifPixelYDimension] as? Int == 300)
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] == [400])
        let gps = try #require(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        #expect(gps[kCGImagePropertyGPSLatitude] as? Double == 52.5)
        #expect(gps[kCGImagePropertyGPSLongitude] as? Double == 13.4)
        #expect(AlbumExporter.embeddedFingerprint(of: output) == rotated.fingerprint)
    }
}
