import CoreImage

/// Highlights/shadows by single-image exposure fusion (after Mertens, Kautz, Van Reeth, "Exposure Fusion", 2007).
///
/// 1. Three synthetic exposures of the image: the image itself, one shifted by the shadows slider and one shifted
///    by the highlights slider (`fusionExposure`). Each is converted to a perceptual (gamma 2.2) scale, where the
///    blending happens; brightened exposures are soft-clipped so they never turn into flat white.
/// 2. Per-pixel weights from the original's perceptual luminance (`fusionWeights`): the shadows exposure wins in
///    dark areas, the highlights exposure in bright areas, the original everywhere else. Weights sum to 1.
/// 3. Multi-scale blend: Laplacian pyramids of the exposures are mixed level by level with a Gaussian pyramid of the
///    weights, then collapsed (`fusionBlend`). Coarse levels see blurred weights, so large dark or bright areas move
///    as a whole while fine detail keeps its local contrast. That is what avoids the halos and flat look of
///    single-scale masks.
///
/// The pyramid always ends at roughly the same fraction of the image, so a screen-sized preview and the full-size
/// export look the same. Kernels use the string-based Core Image Kernel Language: deprecated, but Core Image still
/// translates it to Metal at runtime and it needs no Metal toolchain or build flags.
enum ExposureFusion {
    private typealias Constants = EditRenderer.HighlightsShadows

    private static let exposure = makeKernel("""
        kernel vec4 fusionExposure(__sample s, float gain, float knee) {
            vec3 c = max(s.rgb, vec3(0.0)) * gain;
            if (gain > 1.0) {
                vec3 over = max(c - vec3(knee), vec3(0.0));
                c = min(c, vec3(knee)) + (1.0 - knee) * (vec3(1.0) - exp(-over / (1.0 - knee)));
            }
            c = min(c, vec3(1.0));
            return vec4(pow(c, vec3(1.0 / 2.2)), 1.0);
        }
        """)

    private static let weights = makeKernel("""
        kernel vec4 fusionWeights(__sample p, vec2 amounts, vec4 masks) {
            float l = dot(p.rgb, vec3(0.2126, 0.7152, 0.0722));
            float ws = amounts.x * (1.0 - smoothstep(masks.x, masks.y, l));
            float wh = amounts.y * smoothstep(masks.z, masks.w, l);
            return vec4(vec3(1.0, ws, wh) / (1.0 + ws + wh), 1.0);
        }
        """)

    /// One pyramid level: the weighted sum of the exposures' Laplacian bands (`g - u`) plus the upsampled,
    /// already collapsed coarser levels `r`. On the coarsest level `u` and `r` are black. `highlightDetail` scales the
    /// highlights exposure's band: a darker exposure has flatter detail on the gamma scale, which made recovered
    /// highlights look grey and flat, so fine levels restore (and for recovery, boost) it. Like the local Laplacian
    /// filter's detail remapping, only small differences are amplified: the gain fades out for band values well above
    /// `edge`, so strong edges such as a horizon get no bright outline.
    private static let blend = makeKernel("""
        kernel vec4 fusionBlend(__sample g0, __sample u0, __sample g1, __sample u1, __sample g2, __sample u2,
                                __sample w, __sample r, float highlightDetail, float edge) {
            vec3 h = g2.rgb - u2.rgb;
            float m = dot(h, vec3(0.2126, 0.7152, 0.0722));
            float gain = 1.0 + (highlightDetail - 1.0) * exp(-(m * m) / (2.0 * edge * edge));
            vec3 band = w.r * (g0.rgb - u0.rgb) + w.g * (g1.rgb - u1.rgb) + w.b * h * gain;
            return vec4(band + r.rgb, 1.0);
        }
        """)

    private static let toLinear = makeKernel("""
        kernel vec4 fusionToLinear(__sample p, __sample original) {
            return vec4(pow(max(p.rgb, vec3(0.0)), vec3(2.2)), original.a);
        }
        """)

    // Each kernel is compiled once; the deprecation warning comes from here.
    private static func makeKernel(_ source: String) -> CIColorKernel? {
        CIColorKernel(source: source)
    }

    static func apply(shadows: Double, highlights: Double, to image: CIImage) -> CIImage {
        guard let exposure, let weights, let blend, let toLinear else { return image }
        let extent = image.extent
        guard extent.width >= 2, extent.height >= 2 else { return image }

        let gains = [1, Constants.shadowGain(shadows), Constants.highlightGain(highlights)]
        let exposures = gains.compactMap {
            exposure.apply(extent: extent, arguments: [image, $0, Constants.softClipKnee])
        }
        guard exposures.count == 3 else { return image }

        let masks = CIVector(
            x: Constants.shadowMask.lowerBound, y: Constants.shadowMask.upperBound,
            z: Constants.highlightMask.lowerBound, w: Constants.highlightMask.upperBound
        )
        let amounts = CIVector(
            x: abs(shadows) / 100 * Constants.maxWeight, y: abs(highlights) / 100 * Constants.maxWeight
        )
        guard let weightImage = weights.apply(extent: extent, arguments: [exposures[0], amounts, masks]) else {
            return image
        }

        let levels = levelCount(for: extent.size)
        let exposurePyramids = exposures.map { gaussianPyramid($0, levels: levels) }
        let weightPyramid = gaussianPyramid(weightImage, levels: levels)

        let black = CIImage.black
        let fineLevels = max(1, levels / 2)
        let highlightDetail = Constants.highlightDetailGain(highlights)
        var collapsed: CIImage?
        for level in stride(from: levels, through: 0, by: -1) {
            let levelExtent = weightPyramid[level].extent
            let isCoarsest = level == levels
            var arguments: [Any] = []
            for pyramid in exposurePyramids {
                arguments.append(pyramid[level])
                arguments.append(isCoarsest ? black : upsample(pyramid[level + 1], to: levelExtent))
            }
            arguments.append(weightPyramid[level])
            arguments.append(collapsed.map { upsample($0, to: levelExtent) } ?? black)
            arguments.append(level < fineLevels && !isCoarsest ? highlightDetail : 1.0)
            arguments.append(Constants.detailEdge)
            guard let result = blend.apply(extent: levelExtent, arguments: arguments) else { return image }
            collapsed = isCoarsest || level == 0 ? result : result.insertingIntermediate(cache: false)
        }
        guard let collapsed else { return image }
        return toLinear.apply(extent: extent, arguments: [collapsed, image]) ?? image
    }

    /// Levels below full size, so the coarsest level is about `coarsestSide` pixels on its short side.
    static func levelCount(for size: CGSize) -> Int {
        let shortSide = min(size.width, size.height)
        return max(0, Int(log2(shortSide / Constants.coarsestSide).rounded()))
    }

    private static func gaussianPyramid(_ image: CIImage, levels: Int) -> [CIImage] {
        var pyramid = [image]
        for _ in 0..<levels {
            pyramid.append(downsample(pyramid[pyramid.count - 1]))
        }
        return pyramid
    }

    /// Blur and halve. The input is clamped first so the edges do not fade to transparent.
    private static func downsample(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let target = CGRect(x: 0, y: 0, width: (extent.width / 2).rounded(.up), height: (extent.height / 2).rounded(.up))
        return image.clampedToExtent()
            .applyingGaussianBlur(sigma: 1)
            .transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            .cropped(to: target)
            .insertingIntermediate(cache: false)
    }

    /// Double and smooth, cropped to the finer level's extent. Collapsing uses the same function as building the
    /// Laplacian bands, so reconstruction is exact whatever its filter quality.
    private static func upsample(_ image: CIImage, to extent: CGRect) -> CIImage {
        image.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: 2, y: 2))
            .applyingGaussianBlur(sigma: 1)
            .cropped(to: extent)
    }
}
