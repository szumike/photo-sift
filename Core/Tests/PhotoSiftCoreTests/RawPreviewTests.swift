import CoreGraphics
import Foundation
import PhotoSiftTestSupport
import Testing

@testable import PhotoSiftCore

private let sampleRaw = URL(fileURLWithPath: "/Users/michalszuscik/Documents/PERSONAL/photo-sift/assets/DSC01906.ARW")

@Suite struct RawPreviewTests {
    @Test(.enabled(if: FileManager.default.fileExists(atPath: sampleRaw.path)))
    func decodesRealRawScaledAndCached() async throws {
        let item = PhotoItem(id: "DSC01906", rawURL: sampleRaw, sidecarURL: sampleRaw.appendingPathExtension("xmp"))
        let loader = ImageLoader()

        let clock = ContinuousClock()
        let start = clock.now
        let image = try await loader.rawPreview(for: item, maxPixelSize: 2560)
        print("RAW decode took \(clock.now - start), \(image.width)x\(image.height)")

        #expect(max(image.width, image.height) <= 2560)
        #expect(abs(Double(image.width) / Double(image.height) - 1.5) < 0.01)

        let hits = await loader.cacheHitCount
        let again = try await loader.rawPreview(for: item, maxPixelSize: 2560)
        #expect(again === image)
        #expect(await loader.cacheHitCount == hits + 1)
    }

    @Test func throwsNoRawForJpegOnlyPhoto() async throws {
        let folder = try FixtureFolder.make(.init(jpegOnly: ["A"]))
        let item = PhotoItem(id: "A", jpegURL: folder.url.appendingPathComponent("A.JPG"), sidecarURL: folder.url.appendingPathComponent("A.xmp"))
        let loader = ImageLoader()
        await #expect(throws: ImageLoaderError.self) {
            try await loader.rawPreview(for: item, maxPixelSize: 1000)
        }
    }
}
