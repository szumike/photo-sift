import Foundation
import Testing
import PhotoSiftCore
import PhotoSiftTestSupport

@Suite struct PhotoMetadataTests {
    @Test func readsAllFieldsFromFixture() throws {
        let folder = try FixtureFolder.make(.init(jpegOnly: ["DSC00001"]))
        defer { try? FileManager.default.removeItem(at: folder.url) }

        let metadata = PhotoMetadata.read(from: folder.url.appendingPathComponent("DSC00001.JPG"))

        #expect(metadata.camera == "ILCE-7M3")
        #expect(metadata.lens == "FE 24-70mm F2.8 GM")
        #expect(metadata.iso == 400)
        #expect(metadata.aperture == 2.8)
        #expect(metadata.exposureTime == 0.004)
        #expect(metadata.focalLength == 50)
        let date = try #require(metadata.captureDate)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts.year == 2024 && parts.month == 6 && parts.day == 15)
        #expect(parts.hour == 12 && parts.minute == 0 && parts.second == 0)
    }

    @Test func formatsFields() throws {
        let folder = try FixtureFolder.make(.init(jpegOnly: ["DSC00001"]))
        defer { try? FileManager.default.removeItem(at: folder.url) }

        let metadata = PhotoMetadata.read(from: folder.url.appendingPathComponent("DSC00001.JPG"))

        #expect(metadata.formattedISO == "ISO 400")
        #expect(metadata.formattedAperture == "f/2.8")
        #expect(metadata.formattedExposureTime == "1/250 s")
        #expect(metadata.formattedFocalLength == "50 mm")
        #expect(metadata.formattedDate?.isEmpty == false)
    }

    @Test func formatsEdgeValues() {
        #expect(PhotoMetadata(aperture: 4).formattedAperture == "f/4")
        #expect(PhotoMetadata(aperture: 1.8).formattedAperture == "f/1.8")
        #expect(PhotoMetadata(exposureTime: 2).formattedExposureTime == "2 s")
        #expect(PhotoMetadata(exposureTime: 0.5).formattedExposureTime == "1/2 s")
        #expect(PhotoMetadata(exposureTime: 1.0 / 8000).formattedExposureTime == "1/8000 s")
        #expect(PhotoMetadata(focalLength: 35).formattedFocalLength == "35 mm")
        #expect(PhotoMetadata(focalLength: 24.5).formattedFocalLength == "24.5 mm")
    }

    @Test func missingFieldsAreNilAndFormatToNil() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoMetadataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notAnImage = directory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: notAnImage)

        for metadata in [
            PhotoMetadata.read(from: notAnImage),
            PhotoMetadata.read(from: directory.appendingPathComponent("missing.jpg")),
        ] {
            #expect(metadata == PhotoMetadata())
            #expect(metadata.formattedISO == nil)
            #expect(metadata.formattedAperture == nil)
            #expect(metadata.formattedExposureTime == nil)
            #expect(metadata.formattedFocalLength == nil)
            #expect(metadata.formattedDate == nil)
        }
    }
}
