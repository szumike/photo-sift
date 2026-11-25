import Foundation
import ImageIO
import Testing
import PhotoSiftTestSupport

@Suite struct FixtureFolderTests {
    private func names(in url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    private func properties(of url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func createsRequestedLayout() throws {
        let folder = try FixtureFolder.make(.init(
            pairs: ["DSC00001", "DSC00002"],
            jpegOnly: ["DSC00003"],
            rawOnly: ["DSC00004"],
            darkroom: ["DSC00005"],
            album: ["DSC00006"]
        ))
        defer { try? FileManager.default.removeItem(at: folder.url) }

        #expect(folder.baseNames == ["DSC00001", "DSC00002", "DSC00003", "DSC00004"])
        #expect(try names(in: folder.url) == [
            "Album", "Ciemnia", "DSC00001.ARW", "DSC00001.JPG", "DSC00002.ARW", "DSC00002.JPG",
            "DSC00003.JPG", "DSC00004.ARW",
        ])
        #expect(try names(in: folder.url.appendingPathComponent("Ciemnia")) == ["DSC00005.JPG"])
        #expect(try names(in: folder.url.appendingPathComponent("Album")) == ["DSC00006.JPG"])
    }

    @Test func omitsSubfoldersWhenNotRequested() throws {
        let folder = try FixtureFolder.make(.init(jpegOnly: ["DSC00001"]))
        defer { try? FileManager.default.removeItem(at: folder.url) }

        #expect(try names(in: folder.url) == ["DSC00001.JPG"])
    }

    @Test func jpegHasExpectedSizeAndExif() throws {
        let folder = try FixtureFolder.make(.init(jpegOnly: ["DSC00001", "DSC00002"]))
        defer { try? FileManager.default.removeItem(at: folder.url) }

        let landscape = try properties(of: folder.url.appendingPathComponent("DSC00001.JPG"))
        let portrait = try properties(of: folder.url.appendingPathComponent("DSC00002.JPG"))
        #expect(landscape[kCGImagePropertyPixelWidth] as? Int == 600)
        #expect(landscape[kCGImagePropertyPixelHeight] as? Int == 400)
        #expect(portrait[kCGImagePropertyPixelWidth] as? Int == 400)
        #expect(portrait[kCGImagePropertyPixelHeight] as? Int == 600)

        let exif = try #require(landscape[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] == [400])
        #expect(exif[kCGImagePropertyExifFNumber] as? Double == 2.8)
        #expect(exif[kCGImagePropertyExifExposureTime] as? Double == 0.004)
        #expect(exif[kCGImagePropertyExifFocalLength] as? Double == 50)
        #expect(exif[kCGImagePropertyExifLensModel] as? String == "FE 24-70mm F2.8 GM")
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:06:15 12:00:00")

        let tiff = try #require(landscape[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7M3")
    }

    @Test func arwIsReadableByImageIO() throws {
        let folder = try FixtureFolder.make(.init(rawOnly: ["DSC00001"]))
        defer { try? FileManager.default.removeItem(at: folder.url) }

        let url = folder.url.appendingPathComponent("DSC00001.ARW")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceCreateThumbnailAtIndex(source, 0, nil) != nil)
    }
}
