import PhotoSiftTestSupport
import XCTest

final class CropUITests: XCTestCase {
    /// Throwaway `UserDefaults` suite: the app keeps recents and resume positions here, not in the user\'s defaults.
    private let defaultsSuite = "photosift.uitests.\(UUID().uuidString)"
    private var fixture: FixtureFolder?

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        if let fixture { try? FileManager.default.removeItem(at: fixture.url) }
        fixture = nil
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let folder = try FixtureFolder.make(.init(pairs: ["DSC00001"]))
        fixture = folder
        let app = XCUIApplication()
        app.launchArguments = ["--open-folder", folder.url.path, "--defaults-suite", defaultsSuite]
        app.launch()
        XCTAssertTrue(app.windows["Photo Sift"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["screen.single"].waitForExistence(timeout: 5))
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func center(_ element: XCUIElement) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    /// Pixel size from the label "3:2 · 600 × 400".
    private func cropSize(_ app: XCUIApplication) throws -> (ratio: String, width: Double, height: Double) {
        let text = element(app, "crop.size").text
        let parts = text.components(separatedBy: " · ")
        let numbers = try XCTUnwrap(parts.last).components(separatedBy: " × ").compactMap(Double.init)
        XCTAssertEqual(numbers.count, 2, text)
        return (parts.first ?? "", numbers[0], numbers[1])
    }

    @MainActor
    func testROpensCropOverlayWithHandlesAndGrid() throws {
        let app = try launch()
        app.typeKey("e", modifierFlags: [])
        XCTAssertTrue(element(app, "edit.stage").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "crop.overlay").exists)
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(element(app, "crop.overlay").waitForExistence(timeout: 5))
        for corner in ["nw", "ne", "sw", "se"] {
            XCTAssertTrue(element(app, "crop.handle.\(corner)").exists, corner)
        }
        let size = try cropSize(app)
        XCTAssertEqual(size.ratio, "3:2")
        XCTAssertEqual(size.width, 600)
        XCTAssertEqual(size.height, 400)
    }

    @MainActor
    func testEnterInCropToolLeavesEditMode() throws {
        let app = try launch()
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(element(app, "crop.overlay").waitForExistence(timeout: 5))
        app.typeKey(.enter, modifierFlags: [])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(app, "edit.stage"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertFalse(element(app, "crop.overlay").exists)
    }

    @MainActor
    func testEnterInColourToolStaysInEditMode() throws {
        let app = try launch()
        app.typeKey("e", modifierFlags: [])
        XCTAssertTrue(element(app, "edit.panel").waitForExistence(timeout: 5))
        app.typeKey(.enter, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(element(app, "edit.stage").exists)
    }

    @MainActor
    func testDraggingHandleChangesSizeKeepingRatio() throws {
        let app = try launch()
        app.typeKey("r", modifierFlags: [])
        let handle = element(app, "crop.handle.nw")
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let before = try cropSize(app)
        // `press(forDuration:)` sends no mouse events on macOS; a click that holds and then drags does.
        center(handle).click(forDuration: 0.3, thenDragTo: center(handle).withOffset(CGVector(dx: 120, dy: 80)))
        // Poll the parsed width: the label text alone cannot tell a stale read from a finished resize.
        let deadline = Date().addingTimeInterval(5)
        var after = try cropSize(app)
        while after.width >= before.width, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            after = try cropSize(app)
        }
        XCTAssertLessThan(after.width, before.width)
        XCTAssertEqual(after.ratio, "3:2")
        XCTAssertEqual(after.width / after.height, 1.5, accuracy: 0.02)
    }

    @MainActor
    func testOrientationChangeGivesPortraitRatio() throws {
        let app = try launch()
        app.typeKey("r", modifierFlags: [])
        let portrait = element(app, "edit.orientation.portrait")
        XCTAssertTrue(portrait.waitForExistence(timeout: 5))
        // Buttons inside the `info` scroll view are not hittable for XCUITest: click by coordinate.
        center(portrait).click()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH '2:3' OR value BEGINSWITH '2:3'"),
            object: element(app, "crop.size")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let size = try cropSize(app)
        XCTAssertEqual(size.width / size.height, 2.0 / 3.0, accuracy: 0.02)
    }

    /// M cannot be held by XCUITest, so the hold goes through the panel's "Przed / po" button, which sets the same state.
    @MainActor
    func testHoldingBeforeButtonShowsPrzedLabel() throws {
        let app = try launch()
        app.typeKey("r", modifierFlags: [])
        let button = element(app, "edit.before")
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "stage.beforeLabel").exists)

        // Holding the button blocks the test, so the label is read from another thread meanwhile.
        let observed = LockedBox(false)
        let label = element(app, "stage.beforeLabel")
        DispatchQueue.global().async {
            for _ in 0..<12 where !observed.value {
                Thread.sleep(forTimeInterval: 0.3)
                observed.value = label.exists
            }
        }
        center(button).click(forDuration: 4, thenDragTo: center(button).withOffset(CGVector(dx: 2, dy: 2)))
        XCTAssertTrue(observed.value, "\"Przed\" label shown while the button is held")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }
}

private extension XCUIElement {
    var text: String { (value as? String) ?? label }
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
