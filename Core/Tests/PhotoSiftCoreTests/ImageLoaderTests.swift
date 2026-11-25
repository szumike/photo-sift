import CoreGraphics
import Foundation
import ImageIO
import PhotoSiftTestSupport
import Testing
import UniformTypeIdentifiers

@testable import PhotoSiftCore

@Suite struct ImageLoaderTests {
    private func items(_ spec: FixtureFolder.Spec) throws -> [PhotoItem] {
        let folder = try FixtureFolder.make(spec)
        return folder.baseNames.map { name in
            let jpeg = folder.url.appendingPathComponent("\(name).JPG")
            let raw = folder.url.appendingPathComponent("\(name).ARW")
            let fm = FileManager.default
            return PhotoItem(
                id: name,
                jpegURL: fm.fileExists(atPath: jpeg.path) ? jpeg : nil,
                rawURL: fm.fileExists(atPath: raw.path) ? raw : nil,
                sidecarURL: folder.url.appendingPathComponent("\(name).xmp")
            )
        }
    }

    private func size(_ image: CGImage) -> (Int, Int) { (image.width, image.height) }

    @Test func thumbnailAndPreviewDimensions() async throws {
        // First fixture is 600x400 (landscape), second 400x600 (portrait).
        let photos = try items(.init(jpegOnly: ["A", "B"]))
        let loader = ImageLoader(previewMaxPixelSize: 500)

        let thumb = try await loader.thumbnail(for: photos[0])
        #expect(size(thumb) == (320, 213))
        let portraitThumb = try await loader.thumbnail(for: photos[1])
        #expect(size(portraitThumb) == (213, 320))

        let preview = try await loader.preview(for: photos[0])
        #expect(size(preview) == (500, 333))

        let full = try await loader.fullResolution(for: photos[0])
        #expect(size(full) == (600, 400))
    }

    @Test func appliesExifOrientation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoSiftOrientation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ROT.JPG")
        // Stored 600x400 with orientation 6 (rotate 90 CW): displays as 400x600.
        let context = try #require(CGContext(
            data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let source = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, source, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let photo = PhotoItem(id: "ROT", jpegURL: url, sidecarURL: directory.appendingPathComponent("ROT.xmp"))
        let loader = ImageLoader(previewMaxPixelSize: 300)
        #expect(size(try await loader.thumbnail(for: photo)) == (213, 320))
        #expect(size(try await loader.preview(for: photo)) == (200, 300))
        #expect(size(try await loader.fullResolution(for: photo)) == (400, 600))
    }

    @Test func rawOnlyPhotoUsesEmbeddedPreview() async throws {
        let photos = try items(.init(rawOnly: ["R"]))
        #expect(photos[0].isRawOnly)
        let loader = ImageLoader(previewMaxPixelSize: 500)
        let preview = try await loader.preview(for: photos[0])
        #expect(size(preview) == (500, 333))
        let thumb = try await loader.thumbnail(for: photos[0])
        #expect(size(thumb) == (320, 213))
    }

    @Test func secondReadHitsCache() async throws {
        let photos = try items(.init(jpegOnly: ["A"]))
        let loader = ImageLoader()
        let first = try await loader.preview(for: photos[0])
        #expect(await loader.cacheHitCount == 0)
        let second = try await loader.preview(for: photos[0])
        #expect(await loader.cacheHitCount == 1)
        #expect(first === second)
    }

    @Test func cacheEvictsLeastRecentlyUsed() async throws {
        let photos = try items(.init(jpegOnly: ["A", "B", "C"]))
        let loader = ImageLoader(cacheLimit: 2)
        _ = try await loader.preview(for: photos[0])
        _ = try await loader.preview(for: photos[1])
        _ = try await loader.preview(for: photos[2])
        _ = try await loader.preview(for: photos[0])
        #expect(await loader.cacheHitCount == 0)
        _ = try await loader.preview(for: photos[2])
        #expect(await loader.cacheHitCount == 1)
    }

    @Test func thumbnailsHaveTheirOwnCacheLimit() async throws {
        let photos = try items(.init(jpegOnly: ["A", "B", "C"]))
        let loader = ImageLoader(cacheLimit: 1, thumbnailCacheLimit: 2)
        let preview = try await loader.preview(for: photos[0])
        for photo in photos { _ = try await loader.thumbnail(for: photo) }
        // Thumbnails evicted only thumbnails: the preview survives, the oldest thumbnail is gone.
        #expect(await loader.cachedCount == 3)
        let again = try await loader.preview(for: photos[0])
        #expect(preview === again)
        #expect(await loader.cacheHitCount == 1)
        _ = try await loader.thumbnail(for: photos[0])
        #expect(await loader.cacheHitCount == 1)
    }

    @Test func newPrefetchCancelsPreviousOne() async throws {
        let photos = try items(.init(jpegOnly: ["A", "B", "C", "D"]))
        let loader = ImageLoader()
        await loader.setItems(photos)
        await loader.prefetch(ids: ["A", "B"])
        await loader.prefetch(ids: ["C", "D"])
        for _ in 0..<200 {
            if await loader.cachedCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .milliseconds(100))
        // Whatever of the first batch had not started was cancelled; the second batch always completes.
        let hitsBefore = await loader.cacheHitCount
        _ = try await loader.preview(for: photos[2])
        _ = try await loader.preview(for: photos[3])
        #expect(await loader.cacheHitCount == hitsBefore + 2)
    }

    @Test func prefetchWarmsCache() async throws {
        let photos = try items(.init(jpegOnly: ["A", "B"]))
        let loader = ImageLoader()
        await loader.setItems(photos)
        await loader.prefetch(ids: ["A", "B", "missing"])
        for _ in 0..<200 {
            if await loader.cachedCount == 2 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        _ = try await loader.preview(for: photos[0])
        #expect(await loader.cacheHitCount == 1)
    }

    @Test func throwsWithoutSource() async {
        let photo = PhotoItem(id: "X", sidecarURL: URL(fileURLWithPath: "/tmp/X.xmp"))
        await #expect(throws: ImageLoaderError.self) {
            try await ImageLoader().thumbnail(for: photo)
        }
    }
}
