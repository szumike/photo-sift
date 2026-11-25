import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generates a session folder in a temporary directory for tests.
/// "ARW" files are JPEGs with the `.ARW` extension; ImageIO reads their preview like an embedded thumbnail.
public struct FixtureFolder: Sendable {
    public struct Spec: Sendable {
        public var pairs: [String]
        public var jpegOnly: [String]
        public var rawOnly: [String]
        public var darkroom: [String]
        public var album: [String]
        /// EXIF/TIFF orientation (1...8) written into every generated JPEG; nil writes none.
        public var orientation: Int?
        /// Adds a GPS dictionary to every generated JPEG.
        public var includeGPS: Bool

        public init(
            pairs: [String] = [],
            jpegOnly: [String] = [],
            rawOnly: [String] = [],
            darkroom: [String] = [],
            album: [String] = [],
            orientation: Int? = nil,
            includeGPS: Bool = false
        ) {
            self.pairs = pairs
            self.jpegOnly = jpegOnly
            self.rawOnly = rawOnly
            self.darkroom = darkroom
            self.album = album
            self.orientation = orientation
            self.includeGPS = includeGPS
        }
    }

    public let url: URL
    /// Base names of all photos in the session folder (pairs, JPEG-only, RAW-only), in creation order.
    public let baseNames: [String]

    /// Creates the folder. `darkroom` and `album` names create `Ciemnia/` and `Album/` with a JPEG per name.
    public static func make(_ spec: Spec) throws -> FixtureFolder {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoSiftFixture-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        var index = 0
        func write(_ name: String, extension ext: String, in directory: URL) throws {
            let size = index.isMultiple(of: 2) ? (width: 600, height: 400) : (width: 400, height: 600)
            let data = try jpegData(
                width: size.width, height: size.height, index: index,
                orientation: spec.orientation, includeGPS: spec.includeGPS
            )
            try data.write(to: directory.appendingPathComponent("\(name).\(ext)"), options: .atomic)
            index += 1
        }

        for name in spec.pairs {
            try write(name, extension: "JPG", in: root)
            try write(name, extension: "ARW", in: root)
        }
        for name in spec.jpegOnly { try write(name, extension: "JPG", in: root) }
        for name in spec.rawOnly { try write(name, extension: "ARW", in: root) }

        for (folder, names) in [("Ciemnia", spec.darkroom), ("Album", spec.album)] where !names.isEmpty {
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in names { try write(name, extension: "JPG", in: directory) }
        }

        return FixtureFolder(url: root, baseNames: spec.pairs + spec.jpegOnly + spec.rawOnly)
    }

    private static func jpegData(
        width: Int, height: Int, index: Int, orientation: Int?, includeGPS: Bool
    ) throws -> Data {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw FixtureError.imageCreationFailed }

        // Recognizable pattern: background gradient-ish blocks plus a diagonal stripe and a corner marker.
        let hue = CGFloat(index % 8) / 8
        context.setFillColor(CGColor(red: hue, green: 0.4, blue: 1 - hue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let cell = 50
        for row in 0..<(height / cell) {
            for column in 0..<(width / cell) where (row + column).isMultiple(of: 2) {
                context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
            }
        }
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(12)
        context.move(to: .zero)
        context.addLine(to: CGPoint(x: width, y: height))
        context.strokePath()
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 60, width: 60, height: 60))

        guard let image = context.makeImage() else { throw FixtureError.imageCreationFailed }

        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil
            )
        else { throw FixtureError.imageCreationFailed }

        let seconds = index % 60
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.8,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "SONY",
                kCGImagePropertyTIFFModel: "ILCE-7M3",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "FE 24-70mm F2.8 GM",
                kCGImagePropertyExifISOSpeedRatings: [400],
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifExposureTime: 0.004,
                kCGImagePropertyExifFocalLength: 50.0,
                kCGImagePropertyExifDateTimeOriginal:
                    String(format: "2024:06:15 12:00:%02d", seconds),
            ],
        ]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: "SONY",
                kCGImagePropertyTIFFModel: "ILCE-7M3",
                kCGImagePropertyTIFFOrientation: orientation,
            ]
        }
        if includeGPS {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 52.5,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 13.4,
                kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.imageCreationFailed }
        return data as Data
    }
}

public enum FixtureError: Error {
    case imageCreationFailed
}
