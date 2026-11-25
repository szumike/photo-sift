import AppKit
import PhotoSiftCore
import SwiftUI

/// App-wide state: the open session, the screen it implies, overlays and sheets.
/// Screens read it with `@Environment(AppModel.self)`; `ImageLoader` is `model.loader`.
@MainActor @Observable
final class AppModel {
    enum Screen { case start, emptyFolder, browse }
    enum Sheet: Identifiable {
        case darkroom, export
        var id: Self { self }
    }

    private(set) var session: Session?
    private(set) var isEmptyFolder = false
    var sheet: Sheet?
    var showShortcuts = false
    /// Whether the single-view filmstrip is collapsed; persisted under `ui.filmstripHidden`.
    var filmstripHidden: Bool {
        didSet { defaults.set(filmstripHidden, forKey: Self.filmstripHiddenKey) }
    }

    /// Zoom level of the hold-to-zoom, relative to one image pixel per physical screen pixel (1 = 100%);
    /// one of `zoomLevels`, persisted under `ui.zoomLevel`.
    var zoomLevel: Double {
        didSet { defaults.set(zoomLevel, forKey: Self.zoomLevelKey) }
    }
    static let zoomLevels: [Double] = [1, 1.5, 2, 3]

    /// Where "Do Ciemni" sends the RAWs; persisted under `darkroom.target`.
    var darkroomTarget: DarkroomTarget {
        didSet { defaults.set(darkroomTarget.rawValue, forKey: Self.darkroomTargetKey) }
    }

    let viewState = ViewState()
    let loader = ImageLoader()
    @ObservationIgnored let recentFoldersStore: RecentFoldersStore
    @ObservationIgnored let resumeStore: ResumeStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let filmstripHiddenKey = "ui.filmstripHidden"
    @ObservationIgnored private static let zoomLevelKey = "ui.zoomLevel"
    @ObservationIgnored private static let darkroomTargetKey = "darkroom.target"
    @ObservationIgnored private let keyboard = KeyboardRouter()
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    /// `defaults` is where recents and resume positions are kept; UI tests pass a throwaway suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        filmstripHidden = defaults.bool(forKey: Self.filmstripHiddenKey)
        let storedZoom = defaults.double(forKey: Self.zoomLevelKey)
        zoomLevel = Self.zoomLevels.contains(storedZoom) ? storedZoom : 1
        darkroomTarget = defaults.string(forKey: Self.darkroomTargetKey).flatMap(DarkroomTarget.init) ?? .folder
        recentFoldersStore = RecentFoldersStore(defaults: defaults)
        resumeStore = ResumeStore(defaults: defaults)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.session?.flushPendingSaves() }
        }
    }

    /// "100%", "150%", ... for the active zoom level.
    var zoomLabel: String { "\(Int((zoomLevel * 100).rounded()))%" }

    var screen: Screen {
        session == nil ? .start : (isEmptyFolder ? .emptyFolder : .browse)
    }

    /// Installs the keyboard router and opens the `--open-folder` folder, once.
    func start(opening folder: URL?) {
        guard !didStart else { return }
        didStart = true
        keyboard.install(model: self)
        if let folder { openFolder(folder) }
    }

    // MARK: Folder

    func openFolder(_ url: URL) {
        session?.flushPendingSaves()
        let folder = url.standardizedFileURL
        let newSession: Session
        do {
            newSession = try Session(folder: folder, resumeID: resumeStore.lastPhotoID(in: folder))
        } catch {
            show(Toast("Nie udało się otworzyć folderu", subtext: folder.path))
            return
        }
        session = newSession
        isEmptyFolder = newSession.photos.isEmpty
        sheet = nil
        showShortcuts = false
        viewState.resetHolds()
        recentFoldersStore.record(RecentFolder(
            name: folder.lastPathComponent, path: folder.path, photoCount: newSession.photos.count, date: Date()
        ))
        let photos = newSession.photos
        Task { await loader.setItems(photos) }
        recordPosition()
        if let toast = newSession.toast { show(toast, from: newSession) }
    }

    /// Asks for a folder (folders only) and opens it.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Otwórz"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.openFolder(url) }
        }
    }

    /// Back to the start screen.
    func closeFolder() {
        session?.flushPendingSaves()
        session = nil
        isEmptyFolder = false
        sheet = nil
        showShortcuts = false
        viewState.resetHolds()
    }

    /// Remembers the current photo so the folder reopens on it.
    func recordPosition() {
        guard let session, let id = session.currentID else { return }
        resumeStore.setLastPhotoID(id, in: session.folder)
    }

    // MARK: Messages

    /// Shows a message; one from `from` is also cleared in the session when it expires.
    func show(_ toast: Toast, from session: Session? = nil) {
        viewState.present(toast) {
            if session?.toast?.id == toast.id { session?.dismissToast() }
        }
    }

    // MARK: Shared actions (toolbar and keyboard)

    func toggleEdit() {
        guard let session, session.currentID != nil else { return }
        viewState.isZoomHeld = false
        if session.mode == .edit && session.viewMode == .single {
            session.exitEdit()
        } else {
            session.enterEdit(tool: session.tool)
        }
    }

    func openTool(_ tool: EditTool) {
        guard let session, session.currentID != nil else { return }
        viewState.isZoomHeld = false
        if session.mode == .edit && session.viewMode == .single && session.tool == tool {
            session.exitEdit()
        } else {
            session.enterEdit(tool: tool)
        }
    }

    /// Opens a sheet only when it has something to do.
    func openSheet(_ newSheet: Sheet) {
        guard let session else { return }
        switch newSheet {
        case .darkroom where session.darkroomCount == 0: return
        case .export where session.exportCount == 0: return
        default: break
        }
        showShortcuts = false
        viewState.resetHolds()
        sheet = newSheet
    }
}

/// The window: toolbar, the screen for the current state, messages, shortcuts overlay and sheets.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(ViewState.self) private var viewState

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            MainToolbar()
            content
        }
        .background(Palette.window)
        .foregroundStyle(.white.opacity(0.9))
        .overlay { if model.showShortcuts { ShortcutsOverlay() } }
        .overlay(alignment: .bottom) {
            if let toast = viewState.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewState.toast)
        .sheet(item: $model.sheet) { sheet in
            if let session = model.session {
                switch sheet {
                case .darkroom: DarkroomSheet(session: session)
                case .export: ExportSheet(session: session)
                }
            }
        }
        .onChange(of: model.session?.toast) { _, toast in
            if let toast, let session = model.session { model.show(toast, from: session) }
        }
        .onChange(of: model.session?.currentID) { model.recordPosition() }
        .onChange(of: model.session?.photos) { _, photos in
            if let photos { Task { await model.loader.setItems(photos) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            viewState.resetHolds()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .start:
            StartScreen()
        case .emptyFolder:
            EmptyFolderScreen()
        case .browse:
            if let session = model.session {
                switch session.viewMode {
                case .single: SinglePhotoView(session: session)
                case .grid: GridView(session: session)
                }
            }
        }
    }
}
