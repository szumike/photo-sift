import Foundation
import ImageIO

/// EXIF metadata of a photo, read from the file headers (no image decoding).
public struct PhotoMetadata: Sendable, Equatable {
    public var camera: String?
    public var lens: String?
    public var iso: Int?
    public var aperture: Double?
    public var exposureTime: Double?
    public var focalLength: Double?
    public var captureDate: Date?

    public init(
        camera: String? = nil,
        lens: String? = nil,
        iso: Int? = nil,
        aperture: Double? = nil,
        exposureTime: Double? = nil,
        focalLength: Double? = nil,
        captureDate: Date? = nil
    ) {
        self.camera = camera
        self.lens = lens
        self.iso = iso
        self.aperture = aperture
        self.exposureTime = exposureTime
        self.focalLength = focalLength
        self.captureDate = captureDate
    }

    /// Reads the metadata of an image file. Missing or unreadable fields stay `nil`.
    public static func read(from url: URL) -> PhotoMetadata {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, options),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return PhotoMetadata() }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        let camera = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        let lens = (exif[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespaces)

        return PhotoMetadata(
            camera: camera?.isEmpty == false ? camera : nil,
            lens: lens?.isEmpty == false ? lens : nil,
            iso: (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue,
            aperture: (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
            exposureTime: (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
            focalLength: (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue,
            captureDate: (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(parseExifDate)
        )
    }

    // MARK: Formatting (as in the prototype: "ISO 400", "f/4", "1/250 s", "35 mm")

    public var formattedISO: String? { iso.map { "ISO \($0)" } }

    public var formattedAperture: String? {
        aperture.map { "f/\(Self.trimmed($0, maxFractionDigits: 1))" }
    }

    public var formattedExposureTime: String? {
        guard let exposureTime, exposureTime > 0 else { return nil }
        if exposureTime >= 1 { return "\(Self.trimmed(exposureTime, maxFractionDigits: 1)) s" }
        return "1/\(Int((1 / exposureTime).rounded())) s"
    }

    public var formattedFocalLength: String? {
        focalLength.map { "\(Self.trimmed($0, maxFractionDigits: 1)) mm" }
    }

    public var formattedDate: String? {
        captureDate.map { $0.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "pl_PL"))) }
    }

    private static func trimmed(_ value: Double, maxFractionDigits: Int) -> String {
        let formatted = String(format: "%.\(maxFractionDigits)f", value)
        guard formatted.contains(".") else { return formatted }
        var result = formatted
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    private static func parseExifDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }
}
