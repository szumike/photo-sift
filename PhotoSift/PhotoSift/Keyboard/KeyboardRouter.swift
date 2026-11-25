import AppKit
import PhotoSiftCore

/// Maps every shortcut of `docs/workflow.md` to `Session` and `AppModel` actions.
///
/// Uses a local `NSEvent` monitor, so it sees keyUp (hold Z and M) and ⌘-shortcuts before the menu does,
/// whatever view has focus. A text field or a focused slider keeps its own keys.
@MainActor
final class KeyboardRouter {
    private enum Key: Equatable {
        case left, right, up, down, delete, enter, escape
        case character(String)

        init(_ event: NSEvent) {
            switch event.keyCode {
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            case 51, 117: self = .delete
            case 36, 76: self = .enter
            case 53: self = .escape
            default:
                if event.characters == "?" {
                    self = .character("?")
                } else {
                    self = .character(event.charactersIgnoringModifiers?.lowercased() ?? "")
                }
            }
        }

        var isArrow: Bool { [.left, .right, .up, .down].contains(self) }
    }

    private weak var model: AppModel?
    private var monitor: Any?

    func install(model: AppModel) {
        guard monitor == nil else { return }
        self.model = model
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event was handled and must not travel further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let model, let window = NSApp.keyWindow, !(window is NSPanel), window.sheetParent == nil,
              window.identifier?.rawValue.contains("Settings") != true else { return false }
        let key = Key(event)
        if event.type == .keyUp {
            releaseHold(key, model.viewState)
            return false
        }
        if let responder = window.firstResponder {
            if responder is NSText { return false }
            if responder is NSSlider && key.isArrow { return false }
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if model.showShortcuts {
            guard key == .escape || key == .character("?") else { return false }
            model.showShortcuts = false
            return true
        }
        if model.sheet != nil { return false }
        if modifiers == .command && key == .character("o") {
            model.chooseFolder()
            return true
        }
        if modifiers == .shift && key == .character("?") {
            model.showShortcuts = true
            return true
        }
        guard let session = model.session else { return false }
        guard model.screen == .browse else { return false }
        if event.isARepeat && modifiers.isEmpty && [.character("z"), .character("m"), .character("c"), .delete].contains(key) { return true }
        return session.viewMode == .grid
            ? handleGrid(key, modifiers, session, model)
            : handleSingle(key, modifiers, session, model)
    }

    private func releaseHold(_ key: Key, _ viewState: ViewState) {
        if key == .character("z") { viewState.isZoomHeld = false }
        if key == .character("m") { viewState.isBeforeHeld = false }
    }

    private func handleSingle(_ key: Key, _ modifiers: NSEvent.ModifierFlags, _ session: Session, _ model: AppModel) -> Bool {
        let viewState = model.viewState
        switch (modifiers, key) {
        case ([], .right): session.next()
        case ([], .left): session.previous()
        case ([], .delete): session.delete()
        case ([.command, .shift], .character("r")): session.resetEdit()
        case ([], .character("c")): session.toggleDarkroom()
        case ([], .character("e")): model.openTool(.color)
        case ([], .character("r")): model.openTool(.crop)
        case ([], .character("d")): if session.mode == .edit { session.exitEdit() }
        case ([], .character("g")): session.toggleView()
        case ([], .character("z")):
            if canZoom(session) && session.currentID != nil { viewState.isZoomHeld = true }
        case ([], .character("m")):
            if session.currentID != nil { viewState.isBeforeHeld = true }
        case ([], .escape):
            if session.mode == .edit { session.exitEdit() }
        case ([], .enter):
            guard session.mode == .edit, session.tool == .crop else { return false }
            session.exitEdit()
        default: return handleShared(key, modifiers, session)
        }
        return true
    }

    private func handleGrid(_ key: Key, _ modifiers: NSEvent.ModifierFlags, _ session: Session, _ model: AppModel) -> Bool {
        switch (modifiers, key) {
        case ([], .right): session.moveCurrent(by: 1)
        case ([], .left): session.moveCurrent(by: -1)
        case ([], .down): session.moveCurrent(by: model.viewState.gridColumns)
        case ([], .up): session.moveCurrent(by: -model.viewState.gridColumns)
        case ([], .enter): if let id = session.currentID { session.openInSingle(id) }
        case ([], .delete): session.delete()
        case ([], .character("c")): session.toggleDarkroom()
        case ([], .character("g")): session.toggleView()
        case ([], .character("e")): model.openTool(.color)
        case ([], .character("r")): model.openTool(.crop)
        case ([], .escape): session.clearSelection()
        default: return handleShared(key, modifiers, session)
        }
        return true
    }

    /// Shortcuts that behave the same in the single view and the grid.
    private func handleShared(_ key: Key, _ modifiers: NSEvent.ModifierFlags, _ session: Session) -> Bool {
        switch (modifiers, key) {
        case ([.command], .character("z")): session.undoEdit()
        case ([.command, .shift], .character("z")): session.redoEdit()
        case ([.command, .shift], .character("c")): session.copyWhiteBalance()
        case ([.command, .shift], .character("v")): session.pasteWhiteBalance()
        case ([.command], .character("a")): session.selectAll()
        case ([.command], .character("1")): session.setFilter(.all)
        case ([.command], .character("2")): session.setFilter(.darkroom)
        case ([.command], .character("3")): session.setFilter(.edited)
        default: return false
        }
        return true
    }

    /// Zoom is not available while the crop tool is open, unless the photo is locked (then there is no crop).
    private func canZoom(_ session: Session) -> Bool {
        guard session.mode == .edit, session.tool == .crop else { return true }
        return session.currentPhoto.map(session.isEditLocked) ?? true
    }
}
