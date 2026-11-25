public struct SidecarState: Equatable, Sendable {
    public var edit: EditParams?
    public var markedForDarkroom: Bool

    public init(edit: EditParams? = nil, markedForDarkroom: Bool = false) {
        self.edit = edit
        self.markedForDarkroom = markedForDarkroom
    }
}
