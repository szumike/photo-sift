import PhotoSiftTestSupport
import XCTest

final class ShortcutsUITests: XCTestCase {
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
        let folder = try FixtureFolder.make(.init(pairs: ["DSC00001", "DSC00002"]))
        fixture = folder
        let app = XCUIApplication()
        app.launchArguments = ["--open-folder", folder.url.path, "--defaults-suite", defaultsSuite]
        app.launch()
        XCTAssertTrue(app.windows["Photo Sift"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["screen.single"].waitForExistence(timeout: 5))
        return app
    }

    private func row(_ app: XCUIApplication, _ keys: String) -> XCUIElement {
        app.descendants(matching: .any)["shortcut.\(keys)"]
    }

    @MainActor
    func testQuestionMarkOpensAndEscapeCloses() throws {
        let app = try launch()
        let overlay = app.otherElements["overlay.shortcuts"]
        XCTAssertFalse(overlay.exists)

        app.typeKey("?", modifierFlags: .shift)
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Skróty klawiszowe"].exists)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(overlay))
    }

    @MainActor
    func testQuestionMarkTogglesOverlay() throws {
        let app = try launch()
        let overlay = app.otherElements["overlay.shortcuts"]
        app.typeKey("?", modifierFlags: .shift)
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        app.typeKey("?", modifierFlags: .shift)
        XCTAssertTrue(waitForDisappearance(overlay))
    }

    @MainActor
    func testListsMarkDarkroomAndGridShortcuts() throws {
        let app = try launch()
        app.typeKey("?", modifierFlags: .shift)
        XCTAssertTrue(app.otherElements["overlay.shortcuts"].waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "M").exists)
        XCTAssertTrue(row(app, "D").exists)
        XCTAssertTrue(row(app, "G").exists)
        XCTAssertFalse(row(app, "X").exists)
    }

    private func waitForDisappearance(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }
}
