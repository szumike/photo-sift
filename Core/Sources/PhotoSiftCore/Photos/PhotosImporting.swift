import Foundation

/// Where "Do Ciemni" sends the marked RAW files.
public enum DarkroomTarget: String, Sendable, CaseIterable {
    case folder
    case photos
}

public struct PhotosImportReport: Sendable, Equatable {
    /// `PhotoItem.id` → `PHAsset.localIdentifier` of the imported RAW.
    public var assetIDs: [String: String]
    /// `PhotoItem.id` → reason the RAW was not imported.
    public var failures: [String: String]

    public init(assetIDs: [String: String] = [:], failures: [String: String] = [:]) {
        self.assetIDs = assetIDs
        self.failures = failures
    }
}

public enum PhotosImportError: Error, Equatable, Sendable {
    case accessDenied
    case failed(String)
}

/// Imports RAW files into Apple Photos. The real implementation talks to PhotoKit;
/// tests inject a fake.
public protocol PhotosImporting: Sendable {
    /// Adds the RAWs to the album titled `albumTitle` (the first user album with that exact title,
    /// created when there is none). The files are copied, never moved.
    func importRaws(_ items: [(id: String, rawURL: URL)], albumTitle: String) async throws -> PhotosImportReport

    /// Whether the asset still exists in the library.
    func assetExists(_ localIdentifier: String) -> Bool
}
