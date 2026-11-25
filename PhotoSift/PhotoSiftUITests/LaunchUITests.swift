import XCTest

final class LaunchUITests: XCTestCase {
    /// Throwaway `UserDefaults` suite: the app keeps recents and resume positions here, not in the user\'s defaults.
    private let defaultsSuite = "photosift.uitests.\(UUID().uuidString)"
    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    @MainActor
    func testWindowOpensWithTitle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--defaults-suite", defaultsSuite]
        app.launch()
        XCTAssertTrue(app.windows["Photo Sift"].waitForExistence(timeout: 10))
    }
}
