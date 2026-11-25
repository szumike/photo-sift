import CoreGraphics
import CryptoKit
import Foundation

public enum CropOrientation: String, Codable, Sendable {
    case landscape
    case portrait
}

public struct EditParams: Codable, Equatable, Sendable {
    public var crop: CGRect
    public var orientation: CropOrientation
    public var angle: Double
    public var temperature: Double
    public var tint: Double
    /// Exposure in EV; 0 = no change.
    public var exposure: Double

    public init(
        crop: CGRect,
        orientation: CropOrientation,
        angle: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        exposure: Double = 0
    ) {
        self.crop = crop
        self.orientation = orientation
        self.angle = angle
        self.temperature = temperature
        self.tint = tint
        self.exposure = exposure
    }

    private static let fullCrop = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// No-op edit: full-frame crop, orientation following the image's longer side.
    public static func identity(for imageSize: CGSize) -> EditParams {
        EditParams(
            crop: fullCrop,
            orientation: imageSize.height > imageSize.width ? .portrait : .landscape
        )
    }

    public var isIdentity: Bool {
        crop == Self.fullCrop && angle == 0 && temperature == 0 && tint == 0 && exposure == 0
    }

    /// SHA-256 (first 16 bytes, hex) of a canonical fixed-precision representation.
    public var fingerprint: String {
        let canonical = [
            Self.canonical(crop.origin.x), Self.canonical(crop.origin.y),
            Self.canonical(crop.size.width), Self.canonical(crop.size.height),
            orientation.rawValue,
            Self.canonical(angle), Self.canonical(temperature), Self.canonical(tint),
            Self.canonical(exposure),
        ].joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func canonical(_ value: Double) -> String {
        // `+ 0` folds -0.0 into 0.0 so equal values share one representation.
        String(format: "%.6f", value + 0)
    }
}
