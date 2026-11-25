import Foundation
import Photos

/// `PhotosImporting` backed by the system Photos library.
public struct PhotoKitImporter: PhotosImporting {
    public init() {}

    public func importRaws(
        _ items: [(id: String, rawURL: URL)],
        albumTitle: String
    ) async throws -> PhotosImportReport {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw PhotosImportError.accessDenied }

        let existingAlbum = Self.firstAlbum(titled: albumTitle)
        let created = PlaceholderBox()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                var placeholders: [(id: String, placeholder: PHObjectPlaceholder)] = []
                for item in items {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    options.originalFilename = item.rawURL.lastPathComponent
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: item.rawURL, options: options)
                    if let placeholder = request.placeholderForCreatedAsset {
                        placeholders.append((item.id, placeholder))
                    }
                }
                let album =
                    existingAlbum.flatMap { PHAssetCollectionChangeRequest(for: $0) }
                    ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                album.addAssets(placeholders.map(\.placeholder) as NSArray)
                created.value = placeholders.map { ($0.id, $0.placeholder.localIdentifier) }
            }
        } catch {
            throw PhotosImportError.failed(error.localizedDescription)
        }

        var report = PhotosImportReport()
        let createdIDs = Dictionary(created.value, uniquingKeysWith: { first, _ in first })
        for item in items {
            if let identifier = createdIDs[item.id] {
                report.assetIDs[item.id] = identifier
            } else {
                report.failures[item.id] = "Zdjęcia nie utworzyły elementu"
            }
        }
        return report
    }

    public func assetExists(_ localIdentifier: String) -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // Without access the library cannot be asked: assume the asset is still there.
        guard status == .authorized || status == .limited else { return true }
        return PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).count > 0
    }

    private static func firstAlbum(titled title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
    }
}

/// Carries results out of the `performChanges` block, which runs once on a Photos queue.
private final class PlaceholderBox: @unchecked Sendable {
    var value: [(String, String)] = []
}
