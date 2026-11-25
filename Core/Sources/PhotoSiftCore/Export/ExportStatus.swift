public enum SkipReason: Equatable, Sendable {
    /// Marked for or already sent to Ciemnia.
    case darkroom
    /// No JPEG to export.
    case rawOnly
}

public enum ExportStatus: Equatable, Sendable {
    /// No file in Album/.
    case notExported
    /// Our file, up to date.
    case current
    /// Our file, out of date.
    case changed
    case skipped(SkipReason)
    /// Foreign file with the same name; never touched.
    case conflict
}
