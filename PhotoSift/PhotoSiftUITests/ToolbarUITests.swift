import PhotoSiftTestSupport
import XCTest

final class ToolbarUITests: XCTestCase {
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
        return app
    }

    @MainActor
    func testOpensFolderFromLaunchArgument() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        let name = try XCTUnwrap(fixture).url.lastPathComponent
        let folderName = app.staticTexts["toolbar.folderName"]
        XCTAssertTrue(folderName.waitForExistence(timeout: 5))
        XCTAssertEqual(folderName.text, name)
        XCTAssertTrue(app.otherElements["screen.single"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPositionCounterFollowsArrowKeys() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002", "DSC00003"]))
        let position = app.staticTexts["toolbar.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        XCTAssertEqual(position.text, "1 / 3")

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertEqual(position.text, "2 / 3")
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertEqual(position.text, "3 / 3")
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertEqual(position.text, "2 / 3")

        app.buttons["toolbar.previous"].click()
        XCTAssertEqual(position.text, "1 / 3")
        app.buttons["toolbar.next"].click()
        XCTAssertEqual(position.text, "2 / 3")
    }

    @MainActor
    func testExportButtonIsDisabledWithNothingToExport() throws {
        let app = try launch(.init(rawOnly: ["DSC00001"]))
        let export = app.buttons["toolbar.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertFalse(export.isEnabled)
        XCTAssertEqual(export.label, "Eksportuj (0)")
        XCTAssertFalse(app.buttons["toolbar.sendToDarkroom"].isEnabled)
    }

    @MainActor
    func testExportAndDarkroomButtonsEnableWithWork() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        let export = app.buttons["toolbar.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(export.isEnabled)
        XCTAssertEqual(export.label, "Eksportuj (2)")

        let darkroom = app.buttons["toolbar.sendToDarkroom"]
        XCTAssertFalse(darkroom.isEnabled)
        app.typeKey("c", modifierFlags: [])
        XCTAssertTrue(darkroom.waitForExistence(timeout: 2))
        XCTAssertTrue(darkroom.isEnabled)
        XCTAssertEqual(darkroom.label, "Do Ciemni (1)")
        XCTAssertEqual(app.staticTexts["toolbar.position"].text, "1 / 2")
    }
}

private extension XCUIElement {
    /// Static text exposes its string as `value` on macOS; `label` is empty.
    var text: String { (value as? String) ?? label }
}
