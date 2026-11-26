import CoreGraphics
import CoreImage
import Foundation

/// Core Image edit pipeline shared by preview and export:
/// EXIF orientation, rotation by `angle` about the centre, crop, temperature, tint, exposure, highlights and shadows.
public enum EditRenderer {
    /// Slider (-100...100) to colour mapping constants. Kept here so the whole app shares one mapping.
    public enum WhiteBalance {
        public static let neutralKelvin = 6500.0
        /// Kelvin shift of the target white point at a slider value of 100 (positive = warmer).
        public static let kelvinSpan = 2000.0
        /// Tint shift of the target white point at a slider value of 100 (positive = more magenta).
        public static let tintSpan = 50.0

        public static func targetNeutral(temperature: Double, tint: Double) -> CIVector {
            // Core Image treats the target as the white point the scene is lit by, so a lower
            // Kelvin target renders the image warmer.
            CIVector(
                x: neutralKelvin - temperature / 100 * kelvinSpan,
                y: -tint / 100 * tintSpan
            )
        }
    }

    /// Slider (-100...100) to highlights/shadows mapping constants for `ExposureFusion`.
    public enum HighlightsShadows {
        /// Exposure shift (EV) of the synthetic shadows exposure at a slider value of ±100.
        public static let shadowEV = 3.0
        /// Exposure shift (EV) of the synthetic highlights exposure at a slider value of ±100.
        public static let highlightEV = 1.5
        /// Weight of a synthetic exposure (against 1 for the original) at ±100, deep in its tonal range.
        public static let maxWeight = 4.0
        /// Perceptual luminance ranges: shadows fade out across `shadowMask`, highlights fade in across `highlightMask`.
        public static let shadowMask = 0.0...0.6
        public static let highlightMask = 0.45...1.0
        /// Linear value above which a brightened exposure is soft-clipped instead of cut at white.
        public static let softClipKnee = 0.8
        /// Approximate short side (pixels) of the coarsest pyramid level.
        public static let coarsestSide = 24.0

        public static func shadowGain(_ shadows: Double) -> Double { pow(2, shadows / 100 * shadowEV) }
        public static func highlightGain(_ highlights: Double) -> Double { pow(2, highlights / 100 * highlightEV) }
    }

    public enum RenderError: Error {
        case unreadableImage
        case renderFailed
    }

    // CIContext is documented as thread safe.
    private static let context = CIContext()

    /// Loads a JPEG with its EXIF orientation applied.
    public static func loadOriented(from url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw RenderError.unreadableImage
        }
        return image
    }

    /// Applies `params` to an already oriented image. The result's extent starts at the origin.
    public static func apply(_ params: EditParams, to oriented: CIImage) -> CIImage {
        let size = oriented.extent.size
        var image = oriented.transformed(by: CGAffineTransform(
            translationX: -oriented.extent.origin.x, y: -oriented.extent.origin.y
        ))

        if params.angle != 0 {
            // Core Image is y-up, so a clockwise-on-screen rotation is a negative angle.
            let theta = -params.angle * .pi / 180
            image = image.transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
                .concatenating(CGAffineTransform(rotationAngle: theta))
                .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2)))
        }

        let crop = pixelCrop(params.crop, in: size)
        image = image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))

        if params.temperature != 0 || params.tint != 0 {
            let filter = CIFilter(name: "CITemperatureAndTint")!
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: WhiteBalance.neutralKelvin, y: 0), forKey: "inputNeutral")
            filter.setValue(
                WhiteBalance.targetNeutral(temperature: params.temperature, tint: params.tint),
                forKey: "inputTargetNeutral"
            )
            image = filter.outputImage ?? image
        }
        if params.exposure != 0 {
            let filter = CIFilter(name: "CIExposureAdjust")!
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(params.exposure, forKey: kCIInputEVKey)
            image = filter.outputImage ?? image
        }
        image = adjustHighlightsShadows(image, highlights: params.highlights, shadows: params.shadows)
        return image
    }

    private static func adjustHighlightsShadows(_ input: CIImage, highlights: Double, shadows: Double) -> CIImage {
        guard highlights != 0 || shadows != 0 else { return input }
        return ExposureFusion.apply(shadows: shadows, highlights: highlights, to: input)
    }

    /// Renders the edited JPEG at `url` to a bitmap.
    public static func render(url: URL, params: EditParams) throws -> CGImage {
        try render(apply(params, to: loadOriented(from: url)))
    }

    public static func render(_ image: CIImage) throws -> CGImage {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw RenderError.renderFailed
        }
        return cgImage
    }

    /// Crop in canvas pixels, converted from the normalized top-left rect to Core Image's bottom-left origin.
    private static func pixelCrop(_ crop: CGRect, in size: CGSize) -> CGRect {
        let x = (crop.minX * size.width).rounded()
        let width = (crop.width * size.width).rounded()
        let height = (crop.height * size.height).rounded()
        let top = (crop.minY * size.height).rounded()
        return CGRect(x: x, y: size.height - top - height, width: width, height: height)
    }
}
