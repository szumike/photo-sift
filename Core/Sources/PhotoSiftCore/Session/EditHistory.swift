/// Undo and redo stacks of one photo's edit. Each entry is the edit as it was before a step
/// (`nil` = no edit). Kept in memory only, for the lifetime of the session.
struct EditHistory {
    var undo: [EditParams?] = []
    var redo: [EditParams?] = []
}

/// An open edit gesture: the photo it belongs to and, once its first change is made,
/// the edit as it was before that change (`nil` = the photo had no edit).
struct EditGesture {
    let id: String
    var before: EditParams?
    var hasChanged = false
}
