import Foundation

public struct PhotoItem: Identifiable, Sendable, Equatable {
    public let id: String
    public var jpegURL: URL?
    public var rawURL: URL?
    public var sidecarURL: URL
    public var isSentToDarkroom: Bool
    public var captureDate: Date?

    public var isRawOnly: Bool { jpegURL == nil }

    public init(
        id: String,
        jpegURL: URL? = nil,
        rawURL: URL? = nil,
        sidecarURL: URL,
        isSentToDarkroom: Bool = false,
        captureDate: Date? = nil
    ) {
        self.id = id
        self.jpegURL = jpegURL
        self.rawURL = rawURL
        self.sidecarURL = sidecarURL
        self.isSentToDarkroom = isSentToDarkroom
        self.captureDate = captureDate
    }
}
