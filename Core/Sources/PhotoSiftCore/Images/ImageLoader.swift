import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public enum ImageLoaderError: Error, Sendable {
    case noSource(id: String)
    case decodingFailed(URL)
    case noRaw(id: String)
}

/// Decodes images for the UI. Always applies the EXIF orientation.
/// The RAW is decoded only by `rawPreview(for:maxPixelSize:)`; otherwise a RAW-only photo uses the preview embedded in the ARW.
public actor ImageLoader {
    public enum Kind: Hashable, Sendable {
        case thumbnail
        case preview
        case full
    }

    private struct Key: Hashable {
        let id: String
        let kind: Kind
    }

    public static let thumbnailMaxPixelSize = 320
    public static let defaultPreviewMaxPixelSize = 2560

    private let previewMaxPixelSize: Int
    private let cacheLimit: Int
    private let thumbnailCacheLimit: Int
    private var items: [String: PhotoItem] = [:]
    private var cache: [Key: CGImage] = [:]
    private var recency: [Key] = []
    private var prefetchTasks: [Task<Void, Never>] = []
    private var rawCache: [String: CGImage] = [:]
    private var rawRecency: [String] = []
    private let rawCacheLimit = 4
    private static let rawContext = CIContext()

    /// Number of reads served from the cache.
    public private(set) var cacheHitCount = 0
    /// Number of images currently cached.
    public var cachedCount: Int { cache.count }

    /// - Parameters:
    ///   - cacheLimit: images kept for previews and full-resolution decodes (large, so few).
    ///   - thumbnailCacheLimit: thumbnails kept; counted separately so grid scrolling cannot evict previews.
    public init(
        previewMaxPixelSize: Int = ImageLoader.defaultPreviewMaxPixelSize,
        cacheLimit: Int = 64,
        thumbnailCacheLimit: Int = 1024
    ) {
        self.previewMaxPixelSize = previewMaxPixelSize
        self.cacheLimit = max(1, cacheLimit)
        self.thumbnailCacheLimit = max(1, thumbnailCacheLimit)
    }

    /// Registers the photos that `prefetch(ids:)` can resolve. Drops cached images of photos that are gone.
    public func setItems(_ photos: [PhotoItem]) {
        items = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for key in cache.keys where items[key.id] == nil { remove(key) }
    }

    public func thumbnail(for item: PhotoItem) throws -> CGImage {
        try image(for: item, kind: .thumbnail)
    }

    /// Screen-sized preview. For a RAW-only photo it comes from the thumbnail embedded in the ARW.
    public func preview(for item: PhotoItem) throws -> CGImage {
        try image(for: item, kind: .preview)
    }

    /// Full resolution (for 100% zoom). A RAW-only photo is limited to its embedded preview.
    public func fullResolution(for item: PhotoItem) throws -> CGImage {
        try image(for: item, kind: .full)
    }

    /// A real RAW decode (`CIRAWFilter`, as-shot settings, no Photo Sift edit) scaled so its longest side is at most
    /// `maxPixelSize`. Slow, so it is never prefetched; the last few results are cached.
    public func rawPreview(for item: PhotoItem, maxPixelSize: Int) async throws -> CGImage {
        guard let url = item.rawURL else { throw ImageLoaderError.noRaw(id: item.id) }
        let key = "\(item.id)@\(maxPixelSize)"
        if let cached = rawCache[key] {
            cacheHitCount += 1
            rawRecency.removeAll { $0 == key }
            rawRecency.append(key)
            return cached
        }
        let decoded = try await Self.decodeRaw(url, maxPixelSize: maxPixelSize)
        rawCache[key] = decoded
        rawRecency.removeAll { $0 == key }
        rawRecency.append(key)
        while rawRecency.count > rawCacheLimit { rawCache[rawRecency.removeFirst()] = nil }
        return decoded
    }

    /// Warms the preview cache for the given photos in the background. Unknown ids are ignored.
    /// Tasks of a previous call that have not decoded yet are cancelled.
    public func prefetch(ids: [String]) {
        for task in prefetchTasks { task.cancel() }
        prefetchTasks.removeAll()
        for id in ids {
            guard let item = items[id] else { continue }
            prefetchTasks.append(Task { [weak self] in
                await self?.prefetchPreview(item)
            })
        }
    }

    private func prefetchPreview(_ item: PhotoItem) {
        guard !Task.isCancelled else { return }
        _ = try? preview(for: item)
    }

    // MARK: - Private

    private func image(for item: PhotoItem, kind: Kind) throws -> CGImage {
        let key = Key(id: item.id, kind: kind)
        if let cached = cache[key] {
            cacheHitCount += 1
            touch(key)
            return cached
        }
        let decoded = try Self.decode(item, kind: kind, previewMaxPixelSize: previewMaxPixelSize)
        cache[key] = decoded
        touch(key)
        evict(thumbnails: kind == .thumbnail)
        return decoded
    }

    /// Evicts least recently used images of one class (thumbnails, or previews and full-resolution) over its limit.
    private func evict(thumbnails: Bool) {
        let limit = thumbnails ? thumbnailCacheLimit : cacheLimit
        var candidates = recency.filter { ($0.kind == .thumbnail) == thumbnails }
        while candidates.count > limit {
            remove(candidates.removeFirst())
        }
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func remove(_ key: Key) {
        cache[key] = nil
        recency.removeAll { $0 == key }
    }

    private static func decode(_ item: PhotoItem, kind: Kind, previewMaxPixelSize: Int) throws -> CGImage {
        guard let url = item.jpegURL ?? item.rawURL else { throw ImageLoaderError.noSource(id: item.id) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw ImageLoaderError.decodingFailed(url) }

        var options: [CFString: Any] = [kCGImageSourceCreateThumbnailWithTransform: true]
        if item.isRawOnly {
            // Embedded preview only: `...Always` would force decoding the RAW.
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        } else {
            // `...Always` for JPEG: an embedded EXIF thumbnail is far too small.
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        }

        let maxPixelSize: Int
        switch kind {
        case .thumbnail: maxPixelSize = thumbnailMaxPixelSize
        case .preview: maxPixelSize = previewMaxPixelSize
        case .full: maxPixelSize = fullPixelSize(of: source)
        }
        options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ImageLoaderError.decodingFailed(url) }
        return image
    }

    @concurrent nonisolated private static func decodeRaw(_ url: URL, maxPixelSize: Int) async throws -> CGImage {
        guard let filter = CIRAWFilter(imageURL: url) else { throw ImageLoaderError.decodingFailed(url) }
        let native = filter.nativeSize
        let longest = max(native.width, native.height)
        if longest > 0 { filter.scaleFactor = Float(min(1, Double(maxPixelSize) / longest)) }
        guard let output = filter.outputImage,
              let image = rawContext.createCGImage(output, from: output.extent)
        else { throw ImageLoaderError.decodingFailed(url) }
        return image
    }

    private static func fullPixelSize(of source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height, 1)
    }
}
