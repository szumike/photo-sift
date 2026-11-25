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

    /// Slider (-100...100) to highlights/shadows mapping constants. All values are in stops (EV) of
    /// linear light unless noted. See `HighlightsShadowsKernels` for the algorithm.
    public enum HighlightsShadows {
        /// Box radius of the guided filter as a fraction of the image's long side. Radii are in pixels,
        /// so a fixed value would make the screen-sized preview and the full-resolution export differ;
        /// scaling with the image keeps them the same. Larger = smoother, more local-contrast-safe base.
        public static let guidedRadiusFraction = 0.02
        /// Guided filter regularisation in EV^2. The filter uses a steeper form than He et al.,
        /// `a = v^2 / (v^2 + eps^2)` with v the window variance of log2 luminance, so large edges (variance
        /// well above eps, e.g. a 3 EV edge has v = 2.25) keep the base on `L` and get no halo, while fine
        /// texture of about 1 EV peak to peak (v = 0.25) is smoothed into the base and keeps its contrast.
        public static let guidedEpsilon = 0.5
        /// Log-luminance range (log2 of linear Y) stored in the blurred intermediate image. 14 stops
        /// below to 2 above white cover any realistic photo; values outside are clamped.
        public static let logRange = -12.0...2.0

        /// Shift of the base at slider +100 (negative sliders shift the other way). Shadows lift up to
        /// 1.5 EV and highlights recover up to 1.25 EV. Brightening highlights has little headroom, so
        /// its span is smaller (the soft clip below handles the rest).
        public static let shadowSpanEV = 1.5
        public static let highlightRecoverSpanEV = 1.25
        public static let highlightBrightenSpanEV = 0.6

        /// Tonal masks over the smoothed base luminance (log2 of linear Y; mid grey is about -2.5, sRGB
        /// 0.5 is -2.2). Shadows have full weight below `shadowMask.lowerBound` and none above the upper
        /// bound; highlights are the mirror image. The gap in between keeps midtones almost untouched.
        public static let shadowMask = -6.5 ... -2.0
        public static let highlightMask = -2.0 ... -0.4

        /// Soft clip: positive adjustments that would push the brightest channel above `softClipKnee`
        /// are compressed exponentially towards 1, scaling all channels together (hue is preserved).
        public static let softClipKnee = 0.8

        /// Extra saturation (fraction per EV of shadow lift) that offsets the perceived colour loss in
        /// lifted shadows. Subtle: about +9% chroma at the full 1.5 EV lift.
        public static let saturationPerEV = 0.06

        public static func shadowEV(_ shadows: Double) -> Double { shadows / 100 * shadowSpanEV }
        public static func highlightEV(_ highlights: Double) -> Double {
            highlights / 100 * (highlights < 0 ? highlightRecoverSpanEV : highlightBrightenSpanEV)
        }
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
        if params.highlights != 0 || params.shadows != 0 {
            image = HighlightsShadowsKernels.apply(
                shadows: params.shadows, highlights: params.highlights, to: image
            )
        }
        return image
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
