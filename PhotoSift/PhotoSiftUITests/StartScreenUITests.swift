import PhotoSiftTestSupport
import XCTest

final class StartScreenUITests: XCTestCase {
    /// Throwaway `UserDefaults` suite: the app keeps recents and resume positions here, not in the user\'s defaults.
    private let defaultsSuite = "photosift.uitests.\(UUID().uuidString)"
    private var fixtures: [FixtureFolder] = []

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        for fixture in fixtures { try? FileManager.default.removeItem(at: fixture.url) }
        fixtures = []
    }

    @MainActor
    private func launch(opening spec: FixtureFolder.Spec? = nil) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--defaults-suite", defaultsSuite]
        if let spec {
            let folder = try FixtureFolder.make(spec)
            fixtures.append(folder)
            app.launchArguments += ["--open-folder", folder.url.path]
        }
        app.launch()
        XCTAssertTrue(app.windows["Photo Sift"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testShowsStartScreenWithoutArgument() throws {
        let app = try launch()
        XCTAssertTrue(app.otherElements["screen.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["start.openFolder"].exists)
        XCTAssertTrue(app.staticTexts["Pliki JPG i ARW o tej samej nazwie pokażę jako jedno zdjęcie."].exists)
        XCTAssertFalse(app.otherElements["screen.single"].exists)
    }

    @MainActor
    func testEmptyFolderShowsEmptyScreen() throws {
        let app = try launch(opening: .init())
        XCTAssertTrue(app.otherElements["screen.emptyFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ten folder nie zawiera zdjęć"].exists)
        XCTAssertTrue(app.buttons["emptyFolder.openOther"].exists)
        XCTAssertFalse(app.otherElements["screen.start"].exists)
    }

    @MainActor
    func testRecentFoldersListShowsOpenedFolder() throws {
        let first = try launch(opening: .init(pairs: ["DSC00001", "DSC00002"]))
        let name = try XCTUnwrap(fixtures.last).url.lastPathComponent
        XCTAssertTrue(first.otherElements["screen.single"].waitForExistence(timeout: 5))
        first.terminate()

        let app = try launch()
        XCTAssertTrue(app.otherElements["screen.start"].waitForExistence(timeout: 5))
        let recent = app.buttons["start.recent.0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertTrue(recent.label.contains(name), "label: \(recent.label)")

        recent.click()
        XCTAssertTrue(app.otherElements["screen.single"].waitForExistence(timeout: 5))
    }
}
