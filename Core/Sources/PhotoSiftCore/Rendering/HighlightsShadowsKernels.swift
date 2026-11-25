import CoreImage

/// Lightroom-style highlights/shadows in linear light, built from `CIBoxBlur` and small Core Image colour kernels.
///
/// 1. `hsLogLuma` writes the normalised log2 Rec.709 luminance `L` (0...1 over `logRange`) and `L^2`.
/// 2. A self-guided edge-preserving filter (He et al., "Guided Image Filtering") turns `L` into a smooth
///    "base": `a = var^2 / (var^2 + eps^2)` (squared variance: a steeper edge/texture split than the paper's `var / (var + eps)`), `b = mean - a * mean`, `base = box(a) * L + box(b)`, with the box
///    means taken by `CIBoxBlur` (`hsGuidedCoefficients` does the arithmetic). Near an edge the local
///    variance dominates `eps`, so `a` is about 1 and the base follows `L` itself; in flat or lightly
///    textured areas `a` is about 0 and the base is the local mean. Unlike a Gaussian the base therefore
///    never mixes the two sides of an edge, which is what produced bright/dark halos.
/// 3. `hsCombine` builds smooth shadow/highlight masks from the base and shifts it by
///    `shadowEV * shadowMask + highlightEV * highlightMask` stops.
///    Recombining `newLogY = adjustedBase + detail` gives `newY / Y = 2^(adjustedBase - base)`, so the
///    detail cancels: the ratio is a smooth gain field and local contrast survives. The kernel therefore
///    multiplies RGB by that ratio directly (no division, no blow-up in near-black pixels, hue and
///    saturation preserved), then soft-clips and applies the small saturation compensation.
///
/// Kernel route: the Metal toolchain is not installed and a precompiled metallib resource would be a
/// committed binary, so the kernels use the string-based Core Image Kernel Language. It is deprecated,
/// but Core Image still translates it to Metal at runtime, needs no build flags, and works unchanged
/// from the SwiftPM package and the app target.
enum HighlightsShadowsKernels {
    private typealias Constants = EditRenderer.HighlightsShadows

    private static let logLuma = makeKernel("""
        kernel vec4 hsLogLuma(__sample s, vec2 range) {
            float y = dot(max(s.rgb, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
            float l = log2(max(y, exp2(range.x)));
            float n = clamp((l - range.x) / (range.y - range.x), 0.0, 1.0);
            return vec4(n, n * n, 0.0, 1.0);
        }
        """)

    private static let coefficients = makeKernel("""
        kernel vec4 hsGuidedCoefficients(__sample m, float eps) {
            float variance = max(m.g - m.r * m.r, 0.0);
            float v2 = variance * variance;
            float a = v2 / (v2 + eps * eps);
            return vec4(a, m.r * (1.0 - a), 0.0, 1.0);
        }
        """)

    private static let combine = makeKernel("""
        kernel vec4 hsCombine(__sample s, __sample luma, __sample ab,
                              vec4 masks, vec4 amounts, vec2 range) {
            float base = (ab.r * luma.r + ab.g) * (range.y - range.x) + range.x;

            float shadowShift = amounts.x * (1.0 - smoothstep(masks.x, masks.y, base));
            float highlightShift = amounts.y * smoothstep(masks.z, masks.w, base);
            float ratio = exp2(shadowShift + highlightShift);

            vec3 c = max(s.rgb, vec3(0.0));
            vec3 o = c * ratio;
            float peak = max(o.r, max(o.g, o.b));
            float knee = amounts.w;
            if (ratio > 1.0 && peak > knee) {
                float target = knee + (1.0 - knee) * (1.0 - exp(-(peak - knee) / (1.0 - knee)));
                float before = max(c.r, max(c.g, c.b));
                target = max(target, min(before, 1.0));
                o = o * (target / peak);
            }
            float y = dot(o, vec3(0.2126, 0.7152, 0.0722));
            float boost = 1.0 + amounts.z * max(shadowShift, 0.0);
            o = max(vec3(y) + (o - vec3(y)) * boost, vec3(0.0));
            return vec4(o, s.a);
        }
        """)

    // The only deprecation warning in the package comes from here; each kernel is compiled once.
    private static func makeKernel(_ source: String) -> CIColorKernel? {
        CIColorKernel(source: source)
    }

    /// Box mean over a `(2 * radius + 1)` window. `CIBoxBlur` fades to transparent at the extent, so the
    /// input is clamped first and the result cropped back.
    private static func boxMean(_ image: CIImage, radius: Double) -> CIImage {
        image.clampedToExtent().applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: image.extent)
    }

    static func apply(shadows: Double, highlights: Double, to image: CIImage) -> CIImage {
        guard let logLuma, let coefficients, let combine else { return image }
        let extent = image.extent
        let logRange = Constants.logRange
        let span = logRange.upperBound - logRange.lowerBound
        let range = CIVector(x: logRange.lowerBound, y: logRange.upperBound)
        guard let luma = logLuma.apply(extent: extent, arguments: [image, range]) else { return image }

        let radius = max(extent.width, extent.height) * Constants.guidedRadiusFraction
        // eps is given in EV^2; the filter works on log luminance normalised by `span`.
        let eps = Constants.guidedEpsilon / (span * span)
        guard let ab = coefficients.apply(
            extent: extent, arguments: [boxMean(luma, radius: radius), eps]
        ) else { return image }

        let masks = CIVector(
            x: Constants.shadowMask.lowerBound, y: Constants.shadowMask.upperBound,
            z: Constants.highlightMask.lowerBound, w: Constants.highlightMask.upperBound
        )
        let amounts = CIVector(
            x: Constants.shadowEV(shadows), y: Constants.highlightEV(highlights),
            z: Constants.saturationPerEV, w: Constants.softClipKnee
        )
        return combine.apply(
            extent: extent,
            arguments: [image, luma, boxMean(ab, radius: radius), masks, amounts, range]
        ) ?? image
    }
}
