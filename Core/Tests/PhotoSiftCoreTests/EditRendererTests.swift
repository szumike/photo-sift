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

    @Test func shadowsLiftDarkRegionsMuchMoreThanBrightAndMidtones() throws {
        let change = try regionChange { $0.shadows = 100 }
        #expect(change.dark > 25)
        #expect(change.mid < 3)
        #expect(change.bright < 1)
        #expect(change.dark > change.bright * 10)
    }

    @Test func negativeShadowsDeepenDarkRegions() throws {
        let change = try regionChange { $0.shadows = -100 }
        #expect(change.dark < -10)
        #expect(abs(change.mid) < 3)
    }

    @Test func negativeHighlightsDarkenBrightRegionsMuchMoreThanDarkAndMidtones() throws {
        let change = try regionChange { $0.highlights = -100 }
        #expect(change.bright < -25)
        #expect(abs(change.mid) < 3)
        #expect(abs(change.dark) < 1)
    }

    @Test func positiveHighlightsBrightenBrightRegionsWithoutClipping() throws {
        let change = try regionChange { $0.highlights = 100 }
        #expect(change.bright > 5)
        #expect(abs(change.mid) < 3)
        #expect(abs(change.dark) < 1)
        #expect(change.brightMax < 255)
    }

    @Test(arguments: [-100.0, 100.0])
    func shadowsLookTheSameAtAnyScale(shadows: Double) throws {
        let full = try regionChange { $0.shadows = shadows }
        let half = try regionChange({ $0.shadows = shadows }, scale: 0.5)
        #expect(abs(full.dark - half.dark) < 2)
        #expect(abs(full.bright - half.bright) < 2)
    }

    @Test(arguments: [-100.0, 100.0])
    func highlightsLookTheSameAtAnyScale(highlights: Double) throws {
        let full = try regionChange { $0.highlights = highlights }
        let half = try regionChange({ $0.highlights = highlights }, scale: 0.5)
        #expect(abs(full.dark - half.dark) < 2)
        #expect(abs(full.bright - half.bright) < 2)
    }

    @Test func zeroHighlightsAndShadowsLeaveImageUnchanged() throws {
        let params = EditParams.identity(for: size)
        let before = try rgba(EditRenderer.render(tonalImage()))
        let after = try rgba(EditRenderer.render(EditRenderer.apply(params, to: tonalImage())))
        #expect(before == after)
    }

    /// Key regression against washed-out colour: lifting a saturated dark patch keeps its chroma.
    @Test func shadowsKeepChromaOfSaturatedDarkPatch() throws {
        let red = CIImage(color: CIColor(red: 0.30, green: 0.05, blue: 0.04))
            .cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        var params = EditParams.identity(for: size)
        params.shadows = 100
        let before = try rgba(EditRenderer.render(red))
        let after = try rgba(EditRenderer.render(EditRenderer.apply(params, to: red)))
        func chroma(_ data: [UInt8]) -> (saturation: Double, gOverR: Double) {
            let i = (200 * 600 + 300) * 4
            let r = Double(data[i]), g = Double(data[i + 1]), b = Double(data[i + 2])
            return ((max(r, g, b) - min(r, g, b)) / max(r, g, b), g / r)
        }
        let original = chroma(before), lifted = chroma(after)
        #expect(Double(after[(200 * 600 + 300) * 4]) > Double(before[(200 * 600 + 300) * 4]) + 20)
        #expect(abs(lifted.saturation - original.saturation) < 0.06)
        #expect(abs(lifted.gOverR - original.gOverR) < 0.06)
    }

    /// A fine checker inside a dark region keeps its relative contrast (max/min luminance ratio).
    @Test func shadowsPreserveLocalContrast() throws {
        let dark = CIImage(color: CIColor(red: 0.12, green: 0.12, blue: 0.12))
            .cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let bright = CIImage(color: CIColor(red: 0.17, green: 0.17, blue: 0.17))
            .cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let checker = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputCenter": CIVector(x: 0, y: 0), "inputWidth": 4.0, "inputSharpness": 1.0,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let image = bright.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: dark, kCIInputMaskImageKey: checker,
        ])
        var params = EditParams.identity(for: size)
        params.shadows = 100
        func contrast(_ data: [UInt8]) -> Double {
            var lo = 255.0, hi = 0.0
            for y in 100..<300 { for x in 100..<500 {
                let v = Double(data[(y * 600 + x) * 4 + 1])
                lo = min(lo, v); hi = max(hi, v)
            } }
            return hi / lo
        }
        let beforePixels = try rgba(EditRenderer.render(image))
        let afterPixels = try rgba(EditRenderer.render(EditRenderer.apply(params, to: image)))
        let before = contrast(beforePixels), after = contrast(afterPixels)
        let probe = (200 * 600 + 300) * 4 + 1
        #expect(afterPixels[probe] > beforePixels[probe] + 10 || afterPixels[probe + 4] > beforePixels[probe + 4] + 10)
        #expect(before > 1.3)
        #expect(abs(after - before) / before < 0.1)
    }

    /// Halo regression. A hard edge (dark 0.08 next to bright 0.85, as a step and as a square) must not get a
    /// bright or dark band along it: close to the edge each side stays at its far-field level, and the profile
    /// across the edge is monotonic.
    enum HaloShape: CaseIterable { case step, square }

    private func haloImage(_ shape: HaloShape) -> CIImage {
        let bright = CIImage(color: CIColor(red: 0.85, green: 0.85, blue: 0.85)).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let darkColor = CIColor(red: 0.08, green: 0.08, blue: 0.08)
        let rect = shape == .step ? CGRect(x: 0, y: 0, width: 300, height: 400) : CGRect(x: 200, y: 100, width: 200, height: 200)
        return CIImage(color: darkColor).cropped(to: rect).composited(over: bright)
    }

    @Test(arguments: HaloShape.allCases, [(100.0, 0.0), (0.0, -100.0), (100.0, -100.0)])
    func edgesGetNoHalo(shape: HaloShape, sliders: (shadows: Double, highlights: Double)) throws {
        var params = EditParams.identity(for: size)
        params.shadows = sliders.shadows
        params.highlights = sliders.highlights
        let pixels = try rgba(EditRenderer.render(EditRenderer.apply(params, to: haloImage(shape))))
        func value(_ x: Int) -> Double { Double(pixels[(200 * 600 + x) * 4 + 1]) }
        // Edge at x = 300 (step) or x = 200 (square, dark inside); (dark range, bright range).
        let edge = shape == .step ? 300 : 200
        let darkFar = shape == .step ? 100 : 300
        let brightFar = shape == .step ? 500 : 50
        let darkNear = shape == .step ? (edge - 40)..<edge : edge..<(edge + 40)
        let brightNear = shape == .step ? edge..<(edge + 40) : (edge - 40)..<edge
        let tolerance = 5.0
        for x in darkNear { #expect(abs(value(x) - value(darkFar)) <= tolerance, "dark side x=\(x)") }
        for x in brightNear { #expect(abs(value(x) - value(brightFar)) <= tolerance, "bright side x=\(x)") }
        let profile = (edge - 40)..<(edge + 40)
        let sign = shape == .step ? 1.0 : -1.0
        for x in profile.dropFirst() {
            #expect(sign * (value(x) - value(x - 1)) >= -2, "not monotonic at x=\(x)")
        }
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
