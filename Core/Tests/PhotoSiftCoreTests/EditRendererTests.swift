import CoreGraphics
import CoreImage
import Foundation
import PhotoSiftTestSupport
import Testing

@testable import PhotoSiftCore

@Suite struct EditRendererTests {
    /// First fixture photo: 600x400 landscape JPEG.
    private func fixtureJPEG() throws -> URL {
        let folder = try FixtureFolder.make(.init(jpegOnly: ["DSC00001"]))
        return folder.url.appendingPathComponent("DSC00001.JPG")
    }

    private let size = CGSize(width: 600, height: 400)

    @Test func identityKeepsOriginalDimensions() throws {
        let url = try fixtureJPEG()
        let image = try EditRenderer.render(url: url, params: .identity(for: size))
        #expect(image.width == 600)
        #expect(image.height == 400)
    }

    @Test func halfCropIsThreeByTwoInPixels() throws {
        let url = try fixtureJPEG()
        let crop = CropGeometry.constrainCrop(
            CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            orientation: .landscape, angle: 0, imageSize: size
        )
        let params = EditParams(crop: crop, orientation: .landscape)
        let image = try EditRenderer.render(url: url, params: params)
        #expect(image.width == 300)
        #expect(image.height == 200)
    }

    @Test func portraitOrientationGivesTwoByThree() throws {
        let url = try fixtureJPEG()
        let crop = CropGeometry.constrainCrop(
            CGRect(x: 0.4, y: 0.25, width: 0.2, height: 0.5),
            orientation: .portrait, angle: 0, imageSize: size
        )
        let params = EditParams(crop: crop, orientation: .portrait)
        let image = try EditRenderer.render(url: url, params: params)
        #expect(image.width * 3 == image.height * 2)
        #expect(image.width == 120)
        #expect(image.height == 180)
    }

    @Test(arguments: [10.0, -10.0, 25.0], [CropOrientation.landscape, .portrait])
    func constrainedCropHasNoEmptyCorners(angle: Double, orientation: CropOrientation) {
        let crop = CropGeometry.constrainCrop(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            orientation: orientation, angle: angle, imageSize: size
        )
        let ratio = crop.width * size.width / (crop.height * size.height)
        #expect(abs(ratio - CropGeometry.aspectRatio(for: orientation)) < 1e-9)

        // Every crop corner, mapped back into the unrotated image frame, must lie inside it.
        let theta = -angle * .pi / 180
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        for corner in [
            CGPoint(x: crop.minX, y: crop.minY), CGPoint(x: crop.maxX, y: crop.minY),
            CGPoint(x: crop.minX, y: crop.maxY), CGPoint(x: crop.maxX, y: crop.maxY),
        ] {
            let dx = corner.x * size.width - middle.x
            let dy = corner.y * size.height - middle.y
            let x = middle.x + dx * cos(theta) - dy * sin(theta)
            let y = middle.y + dx * sin(theta) + dy * cos(theta)
            #expect(x >= -1e-6 && x <= size.width + 1e-6)
            #expect(y >= -1e-6 && y <= size.height + 1e-6)
        }
    }

    @Test func constrainCropPullsOffCentreCropInside() {
        let crop = CropGeometry.constrainCrop(
            CGRect(x: 0.8, y: 0.8, width: 0.3, height: 0.3),
            orientation: .landscape, angle: 10, imageSize: size
        )
        #expect(crop.minX >= 0 && crop.maxX <= 1 && crop.minY >= 0 && crop.maxY <= 1)
    }

    @Test(arguments: [10.0, -10.0], [CGRect(x: 0, y: 0, width: 1, height: 1),
                                     CGRect(x: 0.7, y: 0.0, width: 0.3, height: 0.3),
                                     CGRect(x: 0.0, y: 0.7, width: 0.3, height: 0.3)])
    func rotatedRenderHasNoEmptyCorners(angle: Double, wanted: CGRect) throws {
        let url = try fixtureJPEG()
        let crop = CropGeometry.constrainCrop(
            wanted, orientation: .landscape, angle: angle, imageSize: size
        )
        let params = EditParams(crop: crop, orientation: .landscape, angle: angle)
        let image = try EditRenderer.render(url: url, params: params)
        #expect(abs(Double(image.width) / Double(image.height) - 1.5) < 0.02)
        let pixels = try rgba(image)
        // Corners (inset from the antialiased edge) are opaque: nothing outside the rotated image.
        let inset = 4
        for (x, y) in [(inset, inset), (image.width - 1 - inset, inset),
                       (inset, image.height - 1 - inset), (image.width - 1 - inset, image.height - 1 - inset)] {
            #expect(pixels[(y * image.width + x) * 4 + 3] == 255)
        }
    }

    @Test func positiveTemperatureWarmsImage() throws {
        let url = try fixtureJPEG()
        let neutral = try meanRedMinusBlue(url: url, temperature: 0)
        let warm = try meanRedMinusBlue(url: url, temperature: 60)
        let cool = try meanRedMinusBlue(url: url, temperature: -60)
        #expect(warm > neutral)
        #expect(cool < neutral)
    }

    @Test func positiveExposureBrightensImage() throws {
        let url = try fixtureJPEG()
        let base = try meanLuma(url: url, exposure: 0)
        #expect(try meanLuma(url: url, exposure: 1) > base)
        #expect(try meanLuma(url: url, exposure: -1) < base)
    }

    /// Synthetic image: left 40% dark grey, right 40% bright grey, a mid-grey band between, `scale` x 600x400.
    private func tonalImage(scale: CGFloat = 1) -> CIImage {
        let dark = CIImage(color: CIColor(red: 0.15, green: 0.15, blue: 0.15)).cropped(to: CGRect(x: 0, y: 0, width: 240, height: 400))
        let mid = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 240, y: 0, width: 120, height: 400))
        let bright = CIImage(color: CIColor(red: 0.85, green: 0.85, blue: 0.85)).cropped(to: CGRect(x: 360, y: 0, width: 240, height: 400))
        return bright.composited(over: mid.composited(over: dark))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Mean channel change (0...255) in the dark, mid and bright regions, away from the tonal boundaries.
    private func regionChange(
        _ edit: (inout EditParams) -> Void, scale: CGFloat = 1
    ) throws -> (dark: Double, mid: Double, bright: Double, brightMax: Double) {
        let base = EditParams.identity(for: size)
        var edited = base
        edit(&edited)
        let before = try rgba(EditRenderer.render(EditRenderer.apply(base, to: tonalImage(scale: scale))))
        let after = try rgba(EditRenderer.render(EditRenderer.apply(edited, to: tonalImage(scale: scale))))
        let width = Int(600 * scale), height = Int(400 * scale)
        func mean(_ data: [UInt8], columns: Range<Int>) -> Double {
            var sum = 0.0, count = 0.0
            for y in 0..<height {
                for x in columns {
                    sum += Double(data[(y * width + x) * 4]) + Double(data[(y * width + x) * 4 + 1]) + Double(data[(y * width + x) * 4 + 2])
                    count += 3
                }
            }
            return sum / count
        }
        let darkColumns = (width / 20)..<(width / 5)
        let midColumns = (width * 2 / 5 + width / 30)..<(width * 3 / 5 - width / 30)
        let brightColumns = (width * 4 / 5)..<(width * 19 / 20)
        let brightMax = brightColumns.map { Double(after[(height / 2 * width + $0) * 4]) }.max() ?? 0
        return (mean(after, columns: darkColumns) - mean(before, columns: darkColumns),
                mean(after, columns: midColumns) - mean(before, columns: midColumns),
                mean(after, columns: brightColumns) - mean(before, columns: brightColumns),
                brightMax)
    }

    @Test func shadowsLiftDarkRegionsMoreThanBright() throws {
        let change = try regionChange { $0.shadows = 100 }
        #expect(change.dark > 10)
        #expect(change.dark > change.bright + 8)
    }

    @Test func negativeHighlightsDarkenBrightRegionsMoreThanDark() throws {
        let change = try regionChange { $0.highlights = -100 }
        #expect(change.bright < -8)
        #expect(change.bright < change.dark - 8)
    }

    @Test func positiveHighlightsBrightenBrightRegions() throws {
        let change = try regionChange { $0.highlights = 100 }
        #expect(change.bright > 2)
        #expect(change.brightMax < 256)
    }

    @Test(arguments: [(100.0, 0.0), (0.0, -100.0), (0.0, 100.0)])
    func previewAndExportLookTheSame(sliders: (shadows: Double, highlights: Double)) throws {
        let edit: (inout EditParams) -> Void = { $0.shadows = sliders.shadows; $0.highlights = sliders.highlights }
        let full = try regionChange(edit)
        let half = try regionChange(edit, scale: 0.5)
        #expect(abs(full.dark - half.dark) < 6)
        #expect(abs(full.bright - half.bright) < 6)
    }

    @Test func zeroHighlightsAndShadowsLeaveImageUnchanged() throws {
        let params = EditParams.identity(for: size)
        let before = try rgba(EditRenderer.render(tonalImage()))
        let after = try rgba(EditRenderer.render(EditRenderer.apply(params, to: tonalImage())))
        #expect(before == after)
    }

    private func meanLuma(url: URL, exposure: Double) throws -> Double {
        var params = EditParams.identity(for: size)
        params.exposure = exposure
        let image = try EditRenderer.render(url: url, params: params)
        let pixels = try rgba(image)
        let count = image.width * image.height
        var sum = 0.0
        for pixel in 0..<count {
            sum += Double(pixels[pixel * 4]) + Double(pixels[pixel * 4 + 1]) + Double(pixels[pixel * 4 + 2])
        }
        return sum / Double(count * 3)
    }

    private func meanRedMinusBlue(url: URL, temperature: Double) throws -> Double {
        var params = EditParams.identity(for: size)
        params.temperature = temperature
        let image = try EditRenderer.render(url: url, params: params)
        let pixels = try rgba(image)
        var red = 0.0, blue = 0.0
        let count = image.width * image.height
        for pixel in 0..<count {
            red += Double(pixels[pixel * 4])
            blue += Double(pixels[pixel * 4 + 2])
        }
        return (red - blue) / Double(count)
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return data
    }
}
