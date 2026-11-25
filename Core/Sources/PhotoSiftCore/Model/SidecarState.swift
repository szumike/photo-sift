public struct SidecarState: Equatable, Sendable {
    public var edit: EditParams?
    public var markedForDarkroom: Bool
    /// `PHAsset.localIdentifier` of the RAW once it was imported into Apple Photos.
    public var photosAssetID: String?

    public init(edit: EditParams? = nil, markedForDarkroom: Bool = false, photosAssetID: String? = nil) {
        self.edit = edit
        self.markedForDarkroom = markedForDarkroom
        self.photosAssetID = photosAssetID
    }
}
