import CoreGraphics
import Foundation

/// Crop geometry in the straightened-image space: the canvas has the size of the (EXIF-oriented) image,
/// the image is rotated about the canvas centre, and `crop` is a rect normalized to that canvas
/// with a top-left origin. Positive angles rotate the image clockwise as displayed.
public enum CropGeometry {
    /// Width / height of a crop in pixels.
    public static func aspectRatio(for orientation: CropOrientation) -> Double {
        switch orientation {
        case .landscape: 3.0 / 2.0
        case .portrait: 2.0 / 3.0
        }
    }

    /// Fits `crop` to the 3:2 (or 2:3) ratio and moves/shrinks it until it lies inside the rotated image,
    /// so no empty corners remain. Keeps the crop's centre and size where possible.
    public static func constrainCrop(
        _ crop: CGRect,
        orientation: CropOrientation,
        angle: Double,
        imageSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return crop }
        let width = Double(imageSize.width)
        let height = Double(imageSize.height)
        let ratio = aspectRatio(for: orientation)
        let theta = angle * .pi / 180
        let cosine = abs(cos(theta))
        let sine = abs(sin(theta))

        // Half-width limit for a crop centred in the image; half-height is half-width / ratio.
        let limit = min(
            (width / 2) / (cosine + sine / ratio),
            (height / 2) / (sine + cosine / ratio)
        )
        let halfWidth = min(Double(crop.width) * width / 2, limit)
        let halfHeight = halfWidth / ratio

        // The centre must keep the crop inside the canvas and, in the image's own (unrotated) frame
        // where the image is the axis-aligned rect [0,W]x[0,H], inside the image. Both sets are convex
        // and contain the canvas middle, so slide the centre towards the middle until both hold.
        let middle = CGPoint(x: width / 2, y: height / 2)
        let extentX = halfWidth * cosine + halfHeight * sine
        let extentY = halfWidth * sine + halfHeight * cosine
        func fits(_ point: CGPoint) -> Bool {
            let local = rotate(point, by: -theta, about: middle)
            let epsilon = 1e-9
            return Double(point.x) >= halfWidth - epsilon && Double(point.x) <= width - halfWidth + epsilon
                && Double(point.y) >= halfHeight - epsilon && Double(point.y) <= height - halfHeight + epsilon
                && Double(local.x) >= extentX - epsilon && Double(local.x) <= width - extentX + epsilon
                && Double(local.y) >= extentY - epsilon && Double(local.y) <= height - extentY + epsilon
        }
        let wanted = CGPoint(x: crop.midX * width, y: crop.midY * height)
        func point(at fraction: Double) -> CGPoint {
            CGPoint(
                x: Double(middle.x) + (Double(wanted.x) - Double(middle.x)) * fraction,
                y: Double(middle.y) + (Double(wanted.y) - Double(middle.y)) * fraction
            )
        }
        var low = 0.0
        var high = 1.0
        if fits(wanted) {
            low = 1
        } else {
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if fits(point(at: mid)) { low = mid } else { high = mid }
            }
        }
        let canvasCentre = point(at: low)

        return CGRect(
            x: (canvasCentre.x - halfWidth) / width,
            y: (canvasCentre.y - halfHeight) / height,
            width: 2 * halfWidth / width,
            height: 2 * halfHeight / height
        )
    }

    private static func rotate(_ point: CGPoint, by theta: Double, about centre: CGPoint) -> CGPoint {
        let dx = Double(point.x - centre.x)
        let dy = Double(point.y - centre.y)
        return CGPoint(
            x: Double(centre.x) + dx * cos(theta) - dy * sin(theta),
            y: Double(centre.y) + dx * sin(theta) + dy * cos(theta)
        )
    }
}
