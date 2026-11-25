import PhotoSiftTestSupport
import XCTest

final class SingleViewUITests: XCTestCase {
    /// Throwaway `UserDefaults` suite: the app keeps recents and resume positions here, not in the user\'s defaults.
    private let defaultsSuite = "photosift.uitests.\(UUID().uuidString)"
    private var fixture: FixtureFolder?

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        if let fixture { try? FileManager.default.removeItem(at: fixture.url) }
        fixture = nil
    }

    @MainActor
    private func launch(_ spec: FixtureFolder.Spec) throws -> XCUIApplication {
        let folder = try FixtureFolder.make(spec)
        fixture = folder
        let app = XCUIApplication()
        app.launchArguments = ["--open-folder", folder.url.path, "--defaults-suite", defaultsSuite]
        app.launch()
        XCTAssertTrue(app.windows["Photo Sift"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["screen.single"].waitForExistence(timeout: 5))
        return app
    }

    /// Waits until the static text with `identifier` shows `expected`.
    @MainActor
    private func expectText(_ app: XCUIApplication, _ identifier: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.staticTexts[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(identifier) missing", file: file, line: line)
        let predicate = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(identifier) is \(element.text), expected \(expected)", file: file, line: line)
    }

    private func files(in folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    @MainActor
    func testShowsMetadataOfCurrentPhoto() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        expectText(app, "info.fileName", "DSC00001")
        expectText(app, "info.iso", "ISO 400")
        expectText(app, "info.aperture", "f/2.8")
        expectText(app, "info.exposureTime", "1/250 s")
        expectText(app, "info.lens", "FE 24-70mm F2.8 GM")
        expectText(app, "info.type", "JPG + ARW")
    }

    @MainActor
    func testDeleteTrashesFilesAndAdvances() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        let folder = try XCTUnwrap(fixture).url
        XCTAssertTrue(try files(in: folder).isSuperset(of: ["DSC00001.JPG", "DSC00001.ARW"]))

        app.typeKey(.delete, modifierFlags: [])

        expectText(app, "info.fileName", "DSC00002")
        XCTAssertEqual(app.staticTexts["toolbar.position"].text, "1 / 2")
        let remaining = try files(in: folder)
        XCTAssertFalse(remaining.contains("DSC00001.JPG"))
        XCTAssertFalse(remaining.contains("DSC00001.ARW"))
        XCTAssertTrue(remaining.isSuperset(of: ["DSC00002.JPG", "DSC00002.ARW", "DSC00003.JPG", "DSC00003.ARW"]))
    }

    @MainActor
    func testCMarksAndStaysOnPhoto() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        expectText(app, "info.fileName", "DSC00001")

        app.typeKey("c", modifierFlags: [])

        XCTAssertEqual(app.buttons["toolbar.sendToDarkroom"].label, "Do Ciemni (1)")
        expectText(app, "info.fileName", "DSC00001")
        XCTAssertEqual(app.staticTexts["toolbar.position"].text, "1 / 3")
        expectText(app, "info.state.darkroom", "Oznaczone")
        XCTAssertTrue(app.descendants(matching: .any)["badge.darkroom"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testHoldingMouseOnPhotoShowsZoomLabel() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        expectText(app, "info.fileName", "DSC00001")
        let label = app.staticTexts["stage.zoomLabel"]
        XCTAssertFalse(label.exists)

        // Holding the button blocks the test, so the label is read from another thread meanwhile.
        // `press(forDuration:)` sends no mouse events on macOS; a click that holds and then drags does.
        let observed = LockedBox<String?>(nil)
        let stage = app.groups["stage.photo"]
        DispatchQueue.global().async {
            for _ in 0..<12 where observed.value != "100%" {
                Thread.sleep(forTimeInterval: 0.3)
                observed.value = label.exists ? label.text : "missing"
            }
        }
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 4, thenDragTo: stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))

        XCTAssertEqual(observed.value, "100%")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    @MainActor
    func testZoomLevelChosenInSettingsShowsInZoomLabel() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        expectText(app, "info.fileName", "DSC00001")

        app.typeKey(",", modifierFlags: .command)
        let picker = app.descendants(matching: .any)["settings.zoomLevel"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["settings.zoomLevel.200"].firstMatch.click()
        app.typeKey("w", modifierFlags: .command)

        let label = app.staticTexts["stage.zoomLabel"]
        let observed = LockedBox<String?>(nil)
        let stage = app.groups["stage.photo"]
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        DispatchQueue.global().async {
            for _ in 0..<12 where observed.value != "200%" {
                Thread.sleep(forTimeInterval: 0.3)
                observed.value = label.exists ? label.text : "missing"
            }
        }
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 4, thenDragTo: stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))

        XCTAssertEqual(observed.value, "200%")
    }

    @MainActor
    func testRightArrowOnLastPhotoStaysOnIt() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        expectText(app, "info.fileName", "DSC00001")
        app.typeKey(.rightArrow, modifierFlags: [])
        expectText(app, "info.fileName", "DSC00002")
        app.typeKey(.rightArrow, modifierFlags: [])

        expectText(app, "info.fileName", "DSC00002")
        XCTAssertEqual(app.staticTexts["toolbar.position"].text, "2 / 2")
    }

    @MainActor
    func testFilmstripToggleHidesAndShowsStrip() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        let strip = app.descendants(matching: .any)["filmstrip"].firstMatch
        let toggle = app.buttons["filmstrip.toggle"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.exists)
        toggle.click()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: strip)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCommandClickInFilmstripSelectsOnlyOne() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        let first = app.buttons["filmstrip.thumb.DSC00001"]
        let second = app.buttons["filmstrip.thumb.DSC00002"]
        let third = app.buttons["filmstrip.thumb.DSC00003"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isSelected)

        second.click()
        XCUIElement.perform(withKeyModifiers: .command) { third.click() }

        XCTAssertEqual(app.staticTexts["toolbar.position"].text, "3 / 3")
        XCTAssertTrue(third.isSelected)
        XCTAssertFalse(first.isSelected)
        XCTAssertFalse(second.isSelected)
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private extension XCUIElement {
    /// Static text exposes its string as `value` on macOS; `label` is empty.
    var text: String { (value as? String) ?? label }
}
