public struct SidecarState: Equatable, Sendable {
    public var edit: EditParams?
    public var markedForDarkroom: Bool
    /// `PHAsset.localIdentifier` of the RAW once it was imported into Apple Photos.
    public var photosAssetID: String?
    /// Moved to the Trash at the start of the next export (X).
    public var markedForDeletion: Bool

    public init(
        edit: EditParams? = nil,
        markedForDarkroom: Bool = false,
        photosAssetID: String? = nil,
        markedForDeletion: Bool = false
    ) {
        self.edit = edit
        self.markedForDarkroom = markedForDarkroom
        self.photosAssetID = photosAssetID
        self.markedForDeletion = markedForDeletion
    }
}
