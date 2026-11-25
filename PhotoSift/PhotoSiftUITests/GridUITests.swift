import PhotoSiftTestSupport
import XCTest

final class GridUITests: XCTestCase {
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
        app.typeKey("g", modifierFlags: [])
        XCTAssertTrue(app.otherElements["screen.grid"].waitForExistence(timeout: 5))
        return app
    }

    private func cell(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)["grid.cell.\(id)"].firstMatch
    }

    private func files(in folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    @MainActor
    private func commandClick(_ element: XCUIElement) {
        XCUIElement.perform(withKeyModifiers: .command) { element.click() }
    }

    @MainActor
    func testGTogglesBetweenGridAndSingle() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        XCTAssertTrue(cell(app, "DSC00001").waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["grid.info"].text, "2 zdjęcia")
        app.typeKey("g", modifierFlags: [])
        XCTAssertTrue(app.otherElements["screen.single"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["screen.grid"].exists)
    }

    @MainActor
    func testDeleteRemovesAllThreeSelectedPhotos() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003", "DSC00004"]))
        let folder = try XCTUnwrap(fixture).url
        XCTAssertTrue(cell(app, "DSC00001").waitForExistence(timeout: 5))
        cell(app, "DSC00001").click()
        commandClick(cell(app, "DSC00002"))
        commandClick(cell(app, "DSC00003"))
        XCTAssertEqual(app.staticTexts["grid.selectionCount"].text, "3 zaznaczone")

        app.typeKey(.delete, modifierFlags: [])

        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cell(app, "DSC00001"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        let remaining = try files(in: folder)
        for name in ["DSC00001", "DSC00002", "DSC00003"] {
            XCTAssertFalse(remaining.contains("\(name).JPG"), name)
            XCTAssertFalse(remaining.contains("\(name).ARW"), name)
        }
        XCTAssertTrue(remaining.isSuperset(of: ["DSC00004.JPG", "DSC00004.ARW"]))
        XCTAssertEqual(app.staticTexts["grid.info"].text, "1 zdjęcie")
    }

    @MainActor
    func testCMarksAllSelected() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        XCTAssertTrue(cell(app, "DSC00001").waitForExistence(timeout: 5))
        cell(app, "DSC00001").click()
        commandClick(cell(app, "DSC00002"))
        commandClick(cell(app, "DSC00003"))

        app.typeKey("c", modifierFlags: [])

        XCTAssertEqual(app.buttons["toolbar.sendToDarkroom"].label, "Do Ciemni (3)")
    }

    @MainActor
    func testEnterOpensPhotoInSingleView() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        XCTAssertTrue(cell(app, "DSC00002").waitForExistence(timeout: 5))
        cell(app, "DSC00002").click()

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.otherElements["screen.single"].waitForExistence(timeout: 5))
        let name = app.staticTexts["info.fileName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.text, "DSC00002")
    }

    @MainActor
    func testCommandTwoFiltersDarkroom() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        XCTAssertTrue(cell(app, "DSC00001").waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["grid.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["grid.empty"].text, "Brak zdjęć w Ciemni")

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(cell(app, "DSC00002").waitForExistence(timeout: 5))
        cell(app, "DSC00002").click()
        app.typeKey("c", modifierFlags: [])
        app.typeKey("2", modifierFlags: .command)

        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cell(app, "DSC00001"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(cell(app, "DSC00002").exists)
        XCTAssertEqual(app.staticTexts["grid.info"].text, "1 zdjęcie · filtr: Ciemnia")
    }
}

private extension XCUIElement {
    /// Static text exposes its string as `value` on macOS; `label` is empty.
    var text: String { (value as? String) ?? label }
}
