import CoreGraphics
import Foundation
import ImageIO
import Observation

/// State and actions of one opened session folder (see `docs/workflow.md`).
@MainActor @Observable
public final class Session {
    public static let lockedEditText = "Tego zdjęcia nie edytujesz w Photo Sift"

    public let folder: URL

    // MARK: State

    /// Every photo of the folder, in display order (deleted photos are removed).
    public private(set) var photos: [PhotoItem]
    public private(set) var states: [PhotoItem.ID: SidecarState] = [:]
    public private(set) var currentID: String?
    /// Multiple ids only in the grid; in the single view it is always the current photo.
    public private(set) var selection: Set<String> = []
    public private(set) var viewMode: ViewMode = .single
    public private(set) var mode: InteractionMode = .browse
    public private(set) var tool: EditTool = .color
    public private(set) var filter: PhotoFilter = .all
    public private(set) var whiteBalanceClipboard: WhiteBalanceClipboard?
    public private(set) var deletedCount = 0
    /// Number of photos to export; refreshed after every action that can change it.
    public private(set) var exportCount = 0
    /// Export status of every photo, refreshed together with `exportCount`.
    public private(set) var exportStatuses: [PhotoItem.ID: ExportStatus] = [:]
    public private(set) var toast: Toast?
    public private(set) var isExporting = false
    public private(set) var exportProgress: ExportProgress?
    /// True while RAWs are being sent to Darkroom (importing into Photos can take a few seconds).
    public private(set) var isSendingToDarkroom = false

    @ObservationIgnored private let store = SidecarStore()
    @ObservationIgnored private let saveDelay: Duration
    /// Per-photo undo/redo history; observed so `canUndo` and `canRedo` update views.
    private var histories: [PhotoItem.ID: EditHistory] = [:]
    /// Ignored so slider ticks do not invalidate views; `isSaved` publishes only the empty/non-empty transitions.
    @ObservationIgnored private var dirty: Set<String> = [] {
        didSet { if (dirty.isEmpty) != isSaved { isSaved = dirty.isEmpty } }
    }
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var sizeCache: [String: CGSize] = [:]
    @ObservationIgnored private var anchorID: String?
    /// The open edit gesture (a slider or crop drag): its photo and the edit before its first change.
    @ObservationIgnored private var gesture: EditGesture?
    /// One exporter for the session's lifetime: its ownership cache keeps re-planning cheap.
    @ObservationIgnored private let exporter: AlbumExporter
    @ObservationIgnored private var exportTask: Task<ExportSummary, Never>?
    @ObservationIgnored private let photosImporter: any PhotosImporting

    // MARK: Init

    /// - Parameters:
    ///   - resumeID: photo to start on (resume); ignored when it is not in the folder.
    ///   - saveDelay: pause after the last edit before it is written to XMP.
    ///   - photosImporter: imports RAWs into Apple Photos for the `.photos` Darkroom target.
    public init(
        folder: URL,
        resumeID: String? = nil,
        saveDelay: Duration = .milliseconds(300),
        photosImporter: any PhotosImporting = PhotoKitImporter()
    ) throws {
        self.folder = folder
        self.saveDelay = saveDelay
        self.photosImporter = photosImporter
        exporter = AlbumExporter(sessionFolder: folder)
        let scanned = try FolderScanner.scan(folder: folder)
        photos = scanned
        for item in scanned {
            states[item.id] = (try? store.read(at: item.sidecarURL)) ?? SidecarState()
        }
        if let resumeID, let index = scanned.firstIndex(where: { $0.id == resumeID }) {
            currentID = resumeID
            toast = Toast("Wznowiono od zdjęcia \(index + 1) z \(scanned.count)")
        } else {
            currentID = scanned.first?.id
        }
        selection = currentID.map { [$0] } ?? []
        anchorID = currentID
        refreshExportCount()
    }

    // MARK: Derived state

    public var visiblePhotos: [PhotoItem] {
        switch filter {
        case .all: photos
        case .darkroom: photos.filter { isMarked($0) || isSent($0) }
        case .edited: photos.filter { states[$0.id]?.edit != nil }
        }
    }

    public var currentPhoto: PhotoItem? { currentID.flatMap(photo(id:)) }

    /// 1-based position of the current photo among the visible ones.
    public var currentPosition: Int? {
        currentID.flatMap { id in visiblePhotos.firstIndex { $0.id == id } }.map { $0 + 1 }
    }

    /// Marked for Darkroom, not sent yet, with a RAW still in the session folder: what the toolbar counts,
    /// the sheet lists and "Do Ciemni" sends, for either target.
    public var darkroomPending: [PhotoItem] {
        photos.filter { isMarked($0) && !isSent($0) && $0.rawURL != nil }
    }

    public var darkroomCount: Int { darkroomPending.count }

    public func photo(id: String) -> PhotoItem? { photos.first { $0.id == id } }
    public func state(of id: String) -> SidecarState { states[id] ?? SidecarState() }
    public func isMarked(_ item: PhotoItem) -> Bool { states[item.id]?.markedForDarkroom ?? false }
    public func isEdited(_ item: PhotoItem) -> Bool { states[item.id]?.edit != nil }

    /// The RAW was imported into Apple Photos (recorded in the XMP).
    public func isInPhotos(_ item: PhotoItem) -> Bool { states[item.id]?.photosAssetID != nil }

    /// The RAW already left for Darkroom: moved to `Ciemnia/` or imported into Photos.
    public func isSent(_ item: PhotoItem) -> Bool { item.isSentToDarkroom || isInPhotos(item) }

    /// Darkroom photos and RAW-only photos cannot be edited.
    public func isEditLocked(_ item: PhotoItem) -> Bool {
        item.isRawOnly || isSent(item) || isMarked(item)
    }

    /// Edit of the current photo, or the identity edit when it has none.
    public var currentEditParams: EditParams? {
        currentPhoto.map(editParams(for:))
    }

    /// Photos an action applies to: the grid selection, otherwise the current photo.
    public var targetIDs: [String] {
        if viewMode == .grid, !selection.isEmpty {
            return visiblePhotos.map(\.id).filter(selection.contains)
        }
        return currentID.map { [$0] } ?? []
    }

    /// False while an edit waits for its delayed XMP write.
    public private(set) var isSaved = true

    public func dismissToast() { toast = nil }

    // MARK: Navigation

    public func next() {
        let visible = visiblePhotos
        guard !visible.isEmpty else { return }
        let index = currentID.flatMap { id in visible.firstIndex { $0.id == id } } ?? -1
        if index + 1 < visible.count {
            setCurrent(visible[index + 1].id)
        }
    }

    public func previous() {
        let visible = visiblePhotos
        guard !visible.isEmpty else { return }
        let index = currentID.flatMap { id in visible.firstIndex { $0.id == id } } ?? 1
        if index > 0 { setCurrent(visible[index - 1].id) }
    }

    /// Moves the current photo by `offset` positions, clamped (grid arrows: ±1 and ±columns).
    public func moveCurrent(by offset: Int) {
        let visible = visiblePhotos
        guard !visible.isEmpty else { return }
        let index = currentID.flatMap { id in visible.firstIndex { $0.id == id } } ?? 0
        setCurrent(visible[min(max(index + offset, 0), visible.count - 1)].id)
    }

    public func setFilter(_ newFilter: PhotoFilter) {
        let previousIndex = currentID.flatMap { id in photos.firstIndex { $0.id == id } } ?? 0
        filter = newFilter
        let visible = visiblePhotos
        if let currentID, visible.contains(where: { $0.id == currentID }) {
            selection.formIntersection(visible.map(\.id))
            return
        }
        let order = Dictionary(uniqueKeysWithValues: photos.enumerated().map { ($1.id, $0) })
        let replacement = visible.first { order[$0.id, default: 0] >= previousIndex } ?? visible.last
        setCurrent(replacement?.id)
    }

    public func toggleView() {
        switch viewMode {
        case .single:
            viewMode = .grid
            mode = .browse
        case .grid:
            viewMode = .single
        }
        selection = currentID.map { [$0] } ?? []
        anchorID = currentID
    }

    public func openInSingle(_ id: String) {
        guard photo(id: id) != nil else { return }
        viewMode = .single
        setCurrent(id)
    }

    /// Plain click selects one; ⌘ toggles and ⇧ extends a range, both only in the grid.
    public func select(_ id: String, modifiers: SelectionModifiers = []) {
        guard photo(id: id) != nil else { return }
        guard viewMode == .grid else {
            setCurrent(id)
            return
        }
        if modifiers.contains(.shift) {
            let visible = visiblePhotos.map(\.id)
            if let anchor = anchorID.flatMap(visible.firstIndex(of:)), let target = visible.firstIndex(of: id) {
                selection = Set(visible[min(anchor, target)...max(anchor, target)])
                currentID = id
                return
            }
        }
        if modifiers.contains(.command) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
                currentID = id
            }
            anchorID = id
            return
        }
        setCurrent(id)
    }

    public func selectAll() {
        guard viewMode == .grid else { return }
        selection = Set(visiblePhotos.map(\.id))
    }

    public func clearSelection() {
        guard viewMode == .grid else { return }
        selection = []
    }

    // MARK: Edit mode

    public func enterEdit(tool newTool: EditTool) {
        viewMode = .single
        mode = .edit
        tool = newTool
        selection = currentID.map { [$0] } ?? []
    }

    public func exitEdit() { mode = .browse }

    // MARK: Decisions

    public func delete() {
        endEditGesture()
        let ids = targetIDs
        guard !ids.isEmpty else { return }
        let visibleBefore = visiblePhotos.map(\.id)
        let firstIndex = visibleBefore.firstIndex { ids.contains($0) } ?? 0

        flushPendingSaves()
        var deleted: [String] = []
        var trashedTypes: [String] = []
        var failed = 0
        for id in ids {
            guard let item = photo(id: id) else { continue }
            let result = PhotoTrasher().trash(item)
            for kind in ["JPEG", "ARW", "XMP"] where result.trashed.contains(where: { Self.fileType($0) == kind }) {
                if !trashedTypes.contains(kind) { trashedTypes.append(kind) }
            }
            if result.isComplete {
                deleted.append(id)
            } else {
                failed += 1
                forget(result.trashed, of: id)
            }
        }
        if !deleted.isEmpty {
            photos.removeAll { deleted.contains($0.id) }
            for id in deleted {
                states[id] = nil
                histories[id] = nil
            }
            deletedCount += deleted.count
            selection.subtract(deleted)
            advanceAfterRemoval(firstIndex: firstIndex)
        }
        refreshExportCount()

        if failed > 0 {
            toast = Toast(
                "Nie przeniesiono do Kosza: \(PolishPlural.photos(failed))",
                subtext: "Sprawdź uprawnienia do plików."
            )
        } else if deleted.count == 1, let id = deleted.first {
            toast = Toast("\(id) w Koszu", subtext: trashSubtext(trashedTypes))
        } else if !deleted.isEmpty {
            toast = Toast("\(PolishPlural.photos(deleted.count)) w Koszu", subtext: trashSubtext(trashedTypes))
        }
    }

    /// Toggles Darkroom on the current photo or the grid selection.
    /// Never moves to another photo.
    public func toggleDarkroom() {
        let items = targetIDs.compactMap(photo(id:))
        guard !items.isEmpty else { return }
        if releaseVanishedPhotosAssets(of: items) > 0 { return }
        let eligible = items.filter { $0.rawURL != nil && !isSent($0) }
        let skipped = items.count - eligible.count

        guard !eligible.isEmpty else {
            if let blocked = items.first {
                toast = isSent(blocked) ? alreadySentToast(blocked) : Toast(Self.noRawText)
            }
            return
        }

        let marking = eligible.contains { !isMarked($0) }
        var changed: [PhotoItem] = []
        for item in eligible where isMarked(item) != marking {
            var state = self.state(of: item.id)
            state.markedForDarkroom = marking
            guard persistNow(state, for: item) else {
                toast = Toast("Nie udało się zapisać pliku XMP", subtext: item.sidecarURL.lastPathComponent)
                continue
            }
            states[item.id] = state
            changed.append(item)
        }
        refreshExportCount()

        let count = changed.count
        guard count > 0 else { return }
        var message: Toast
        if items.count == 1, let item = changed.first {
            message = Toast(marking ? "\(item.id) → Ciemnia" : "\(item.id): bez Ciemni")
        } else {
            let label = PolishPlural.photos(count)
            message = Toast(marking ? "\(label) → Ciemnia" : "\(label): bez Ciemni")
        }
        if skipped > 0 {
            message = Toast(message.text, subtext: "Pominięto \(skipped) (brak RAW lub już w Ciemnia/)")
        }
        toast = message
    }

    // MARK: Edits

    /// Applies `change` to the edit of the current photo; saved to XMP after `saveDelay`.
    /// Returns false (with a toast) when the photo is locked.
    @discardableResult
    public func updateEdit(_ change: (inout EditParams) -> Void) -> Bool {
        guard let item = currentPhoto else { return false }
        guard !isEditLocked(item) else {
            toast = Toast(Self.lockedEditText)
            return false
        }
        let before = states[item.id]?.edit
        var params = editParams(for: item)
        change(&params)
        apply(params, to: item)
        if gesture?.id == item.id {
            if gesture?.hasChanged == false {
                gesture?.before = before
                gesture?.hasChanged = true
            }
        } else {
            recordStep(before: before, for: item.id)
        }
        scheduleSave(item.id)
        return true
    }

    /// Starts an edit gesture on the current photo: until `endEditGesture()` every `updateEdit` forms one undo step.
    public func beginEditGesture() {
        guard gesture == nil, let id = currentID else { return }
        gesture = EditGesture(id: id)
    }

    /// Commits the open gesture as one undo step (a no-op when nothing changed). Safe to call when none is open.
    public func endEditGesture() {
        guard let finished = gesture else { return }
        gesture = nil
        if finished.hasChanged { recordStep(before: finished.before, for: finished.id) }
    }

    /// Whether the current photo has an edit step to undo (false when it is locked).
    public var canUndo: Bool { canStep(\.undo) }
    public var canRedo: Bool { canStep(\.redo) }

    /// Reverts the last edit step of the current photo; a locked photo is left untouched.
    public func undoEdit() {
        endEditGesture()
        step(from: \.undo, to: \.redo)
    }

    public func redoEdit() {
        endEditGesture()
        step(from: \.redo, to: \.undo)
    }

    public func resetEdit() {
        endEditGesture()
        guard let item = currentPhoto else { return }
        guard !isEditLocked(item) else {
            toast = Toast(Self.lockedEditText)
            return
        }
        recordStep(before: states[item.id]?.edit, after: nil, for: item.id)
        states[item.id]?.edit = nil
        saveNow(item.id)
        toast = Toast("Edycja zresetowana")
    }

    public func copyWhiteBalance() {
        guard let item = currentPhoto else { return }
        let params = editParams(for: item)
        whiteBalanceClipboard = WhiteBalanceClipboard(temperature: params.temperature, tint: params.tint)
        toast = Toast(
            "Skopiowano balans bieli",
            subtext: "Temp. \(Self.slider(params.temperature)) · Tint \(Self.slider(params.tint))"
        )
    }

    public func pasteWhiteBalance() {
        endEditGesture()
        guard let clipboard = whiteBalanceClipboard else {
            toast = Toast("Najpierw skopiuj balans bieli")
            return
        }
        var applied = 0
        var skipped = 0
        for item in targetIDs.compactMap(photo(id:)) {
            guard !isEditLocked(item) else {
                skipped += 1
                continue
            }
            var params = editParams(for: item)
            params.temperature = clipboard.temperature
            params.tint = clipboard.tint
            let before = states[item.id]?.edit
            apply(params, to: item)
            recordStep(before: before, for: item.id)
            saveNow(item.id, refreshing: false)
            applied += 1
        }
        if applied > 0 { refreshExportCount() }
        toast = Toast(
            "Wklejono balans bieli: \(PolishPlural.photos(applied))",
            subtext: skipped > 0 ? "Pominięto \(skipped) (Ciemnia lub tylko RAW)" : nil
        )
    }

    /// Writes every edit still waiting for its delayed save. Synchronous and idempotent: call it on the
    /// main actor before quitting (e.g. from the app-termination handler) or before moving files.
    public func flushPendingSaves() {
        guard !dirty.isEmpty else { return }
        for id in dirty { saveNow(id, refreshing: false) }
        refreshExportCount()
    }

    // MARK: Darkroom and export

    /// Sends the marked RAWs to `target`: moved to `Ciemnia/`, or imported into Apple Photos.
    public func sendToDarkroom(target: DarkroomTarget = .folder) async {
        guard !isSendingToDarkroom else { return }
        isSendingToDarkroom = true
        defer { isSendingToDarkroom = false }
        flushPendingSaves()
        switch target {
        case .folder: await moveToDarkroomFolder()
        case .photos: await importIntoPhotos()
        }
    }

    private func moveToDarkroomFolder() async {
        let items = darkroomPending
        guard !items.isEmpty else { return }
        let folder = folder
        let report = await Task.detached { DarkroomMover(sessionFolder: folder).send(items) }.value

        for id in report.moved {
            guard let index = photos.firstIndex(where: { $0.id == id }) else { continue }
            photos[index].rawURL = nil
            photos[index].isSentToDarkroom = true
            states[id] = SidecarState()
            histories[id] = nil
        }
        refreshExportCount()

        var details = ["JPEG-i zostały na miejscu."]
        if !report.conflicts.isEmpty {
            details.append("Konflikty (plik już jest w Ciemnia/): \(report.conflicts.joined(separator: ", ")).")
        }
        if !report.failures.isEmpty {
            details.append("Błędy: \(report.failures.map(\.id).joined(separator: ", ")).")
        }
        toast = Toast(
            "Przeniesiono \(PolishPlural.rawFiles(report.moved.count)) do Ciemnia/",
            subtext: details.joined(separator: " ")
        )
    }

    private func importIntoPhotos() async {
        // Exactly what the toolbar and the sheet show. A photo whose asset vanished from Photos goes back
        // only after C releases it (`releaseVanishedPhotosAssets`), so the sheet never under-reports.
        let items: [(id: String, rawURL: URL)] = darkroomPending.compactMap { item in
            item.rawURL.map { (item.id, $0) }
        }
        guard !items.isEmpty else { return }
        let albumTitle = folder.lastPathComponent

        let report: PhotosImportReport
        do {
            report = try await photosImporter.importRaws(items, albumTitle: albumTitle)
        } catch PhotosImportError.accessDenied {
            toast = Toast(
                "Brak dostępu do Zdjęć",
                subtext: "Zezwól w Ustawieniach systemowych → Prywatność → Zdjęcia."
            )
            return
        } catch {
            let reason = (error as? PhotosImportError).flatMap { error -> String? in
                if case .failed(let message) = error { return message }
                return nil
            } ?? error.localizedDescription
            toast = Toast("Nie udało się dodać do Zdjęć", subtext: reason)
            return
        }

        let failedIDs = report.failures.keys.sorted()
        var unsavedIDs: [String] = []
        var added = 0
        for item in items {
            guard let assetID = report.assetIDs[item.id], let current = photo(id: item.id) else { continue }
            var state = self.state(of: item.id)
            state.photosAssetID = assetID
            // The asset exists even if the XMP write fails: keep it in memory so this session never imports it again.
            if !persistNow(state, for: current) { unsavedIDs.append(item.id) }
            states[item.id] = state
            histories[item.id] = nil
            added += 1
        }
        refreshExportCount()

        var details = ["Album „\(albumTitle)”. Pliki w folderze bez zmian."]
        if !failedIDs.isEmpty {
            details.append("Nie dodano: \(failedIDs.map { "\($0) (\(report.failures[$0] ?? ""))" }.joined(separator: ", ")).")
        }
        if !unsavedIDs.isEmpty {
            details.append("Nie udało się zapisać XMP: \(unsavedIDs.joined(separator: ", ")). Są już w Zdjęciach — po ponownym otwarciu folderu nie wysyłaj ich drugi raz.")
        }
        let title = added == 0 ? "Nie udało się dodać do Zdjęć" : "Dodano \(PolishPlural.rawFiles(added)) do Zdjęć"
        toast = Toast(title, subtext: details.joined(separator: " "))
    }

    /// Clears the stored Photos asset of every photo whose asset the user deleted from the library, so it can be
    /// sent again. Returns how many were cleared (with a toast).
    private func releaseVanishedPhotosAssets(of items: [PhotoItem]) -> Int {
        var released: [String] = []
        for item in items {
            guard let assetID = states[item.id]?.photosAssetID, !photosImporter.assetExists(assetID) else { continue }
            var state = self.state(of: item.id)
            state.photosAssetID = nil
            guard persistNow(state, for: item) else { continue }
            states[item.id] = state
            released.append(item.id)
        }
        guard !released.isEmpty else { return 0 }
        refreshExportCount()
        toast = Toast(
            "\(PolishPlural.photos(released.count)) usunięte ze Zdjęć",
            subtext: "Zdjęcie jest znów oznaczone — możesz wysłać je ponownie."
        )
        return released.count
    }

    public func exportPlan() -> ExportPlan {
        exporter.plan(items: photos, states: states)
    }

    /// Runs the export off the main actor; `cancelExport()` stops it between files.
    @discardableResult
    public func runExport(plan: ExportPlan) async -> ExportSummary {
        guard !isExporting else { return ExportSummary() }
        flushPendingSaves()
        isExporting = true
        let exporter = exporter
        let task = Task.detached { [weak self] in
            await exporter.run(plan: plan) { progress in
                Task { @MainActor in
                    if self?.isExporting == true { self?.exportProgress = progress }
                }
            }
        }
        exportTask = task
        let summary = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        exportTask = nil
        isExporting = false
        exportProgress = nil
        refreshExportCount()

        let written = summary.copied + summary.rendered
        if summary.wasCancelled {
            toast = Toast("Eksport zatrzymany", subtext: "Zapisano \(written) z \(plan.pendingCount).")
        } else if !summary.failed.isEmpty {
            toast = Toast(
                "Wyeksportowano \(PolishPlural.photos(written)) do Album/",
                subtext: "Błędy: \(summary.failed.joined(separator: ", "))."
            )
        } else {
            toast = Toast("Wyeksportowano \(PolishPlural.photos(written)) do Album/")
        }
        return summary
    }

    public func cancelExport() { exportTask?.cancel() }

    // MARK: Helpers

    static let noRawText = "Brak pliku RAW — nie można wysłać do Ciemni"

    private func alreadySentToast(_ item: PhotoItem) -> Toast {
        if isInPhotos(item) {
            return Toast("RAW jest już w Zdjęciach", subtext: "Album „\(folder.lastPathComponent)”.")
        }
        return Toast("RAW jest już w Ciemnia/", subtext: "Cofniesz to, przenosząc \(item.id).ARW w Finderze.")
    }

    private func trashSubtext(_ types: [String]) -> String {
        "\(PolishPlural.list(types)) · przywrócisz w Finderze"
    }

    private static func fileType(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "JPEG"
        case "arw": "ARW"
        case "xmp": "XMP"
        default: url.pathExtension.uppercased()
        }
    }

    private static func slider(_ value: Double) -> String { String(format: "%.0f", value) }

    private func setCurrent(_ id: String?) {
        if id != currentID { endEditGesture() }
        currentID = id
        anchorID = id
        selection = id.map { [$0] } ?? []
    }

    /// After deletion the photo that took the deleted one's place becomes current.
    private func advanceAfterRemoval(firstIndex: Int) {
        let visible = visiblePhotos
        guard !visible.isEmpty else {
            setCurrent(nil)
            return
        }
        setCurrent(visible[min(firstIndex, visible.count - 1)].id)
    }

    private func editParams(for item: PhotoItem) -> EditParams {
        states[item.id]?.edit ?? .identity(for: orientedSize(of: item))
    }

    /// An edit equal to the identity is stored as "no edit".
    private func apply(_ params: EditParams, to item: PhotoItem) {
        var state = self.state(of: item.id)
        state.edit = params.isIdentity ? nil : params
        states[item.id] = state
    }

    /// Pixel size of the JPEG as displayed (EXIF orientation applied); 3:2 when unreadable.
    public func orientedSize(of item: PhotoItem) -> CGSize {
        if let cached = sizeCache[item.id] { return cached }
        var size = CGSize(width: 3, height: 2)
        if
            let url = item.jpegURL,
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary
            ) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        {
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            size = (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }
        sizeCache[item.id] = size
        return size
    }

    private func canStep(_ stack: KeyPath<EditHistory, [EditParams?]>) -> Bool {
        guard let item = currentPhoto, !isEditLocked(item) else { return false }
        return !(histories[item.id]?[keyPath: stack].isEmpty ?? true)
    }

    private func step(
        from source: WritableKeyPath<EditHistory, [EditParams?]>,
        to destination: WritableKeyPath<EditHistory, [EditParams?]>
    ) {
        guard let item = currentPhoto, canStep(source), var history = histories[item.id] else { return }
        let target = history[keyPath: source].removeLast()
        history[keyPath: destination].append(states[item.id]?.edit)
        histories[item.id] = history
        var state = self.state(of: item.id)
        state.edit = target
        states[item.id] = state
        scheduleSave(item.id)
    }

    /// Records the step that turned `before` into the photo's current edit.
    private func recordStep(before: EditParams?, for id: String) {
        recordStep(before: before, after: states[id]?.edit, for: id)
    }

    private func recordStep(before: EditParams?, after: EditParams?, for id: String) {
        guard before != after else { return }
        var history = histories[id] ?? EditHistory()
        history.undo.append(before)
        history.redo.removeAll()
        histories[id] = history
    }

    private func scheduleSave(_ id: String) {
        dirty.insert(id)
        saveTasks[id]?.cancel()
        saveTasks[id] = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow(id)
        }
    }

    private func saveNow(_ id: String, refreshing: Bool = true) {
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        dirty.remove(id)
        guard let item = photo(id: id) else { return }
        if !persistNow(state(of: id), for: item) {
            toast = Toast("Nie udało się zapisać pliku XMP", subtext: item.sidecarURL.lastPathComponent)
        }
        if refreshing { refreshExportCount() }
    }

    /// Writes the state only when the sidecar lies directly in the session folder.
    private func persistNow(_ state: SidecarState, for item: PhotoItem) -> Bool {
        guard item.sidecarURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else {
            return false
        }
        do {
            try store.write(state, to: item.sidecarURL)
            return true
        } catch {
            return false
        }
    }

    /// Drops files that were already trashed from a photo whose deletion only partly succeeded.
    private func forget(_ trashed: [URL], of id: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        if let url = photos[index].jpegURL, trashed.contains(url) { photos[index].jpegURL = nil }
        if let url = photos[index].rawURL, trashed.contains(url) { photos[index].rawURL = nil }
    }

    private func refreshExportCount() {
        let plan = exportPlan()
        exportCount = plan.pendingCount
        exportStatuses = Dictionary(plan.entries.map { ($0.item.id, $0.status) }, uniquingKeysWith: { _, last in last })
    }
}
