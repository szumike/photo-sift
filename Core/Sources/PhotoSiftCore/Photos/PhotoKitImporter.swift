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

        var report = PhotosImportReport()
        let readable = items.filter { item in
            guard FileManager.default.isReadableFile(atPath: item.rawURL.path) else {
                report.failures[item.id] = "nie można odczytać pliku"
                return false
            }
            return true
        }
        guard !readable.isEmpty else { return report }

        do {
            report.assetIDs = try await Self.importBatch(readable, albumTitle: albumTitle)
        } catch where readable.count == 1 {
            report.failures[readable[0].id] = error.localizedDescription
        } catch {
            // PhotoKit rejects the whole transaction when one file is bad: retry one by one to name the culprit.
            for item in readable {
                do {
                    report.assetIDs.merge(try await Self.importBatch([item], albumTitle: albumTitle)) { first, _ in first }
                } catch {
                    report.failures[item.id] = error.localizedDescription
                }
            }
        }
        for item in readable where report.assetIDs[item.id] == nil && report.failures[item.id] == nil {
            report.failures[item.id] = "Zdjęcia nie utworzyły elementu"
        }
        return report
    }

    /// One `performChanges` transaction: creates the assets and adds them to the album (found again each time,
    /// so a retry after the first created it reuses it). Returns `PhotoItem.id` → `localIdentifier`.
    private static func importBatch(
        _ items: [(id: String, rawURL: URL)],
        albumTitle: String
    ) async throws -> [String: String] {
        let existingAlbum = firstAlbum(titled: albumTitle)
        let created = PlaceholderBox()
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
        return Dictionary(created.value, uniquingKeysWith: { first, _ in first })
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
