import PhotoSiftTestSupport
import XCTest

final class ExportSheetUITests: XCTestCase {
    /// Throwaway `UserDefaults` suite: the app keeps recents and resume positions here, not in the user\'s defaults.
    private let defaultsSuite = "photosift.uitests.\(UUID().uuidString)"
    private var fixture: FixtureFolder?

    private let spec = FixtureFolder.Spec(
        pairs: ["DSC00001", "DSC00002", "DSC00003"],
        jpegOnly: ["DSC00004"],
        rawOnly: ["DSC00005"]
    )

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        if let fixture { try? FileManager.default.removeItem(at: fixture.url) }
        fixture = nil
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let folder = try FixtureFolder.make(spec)
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

    @MainActor
    private func openSheet(_ app: XCUIApplication) {
        let button = app.buttons["toolbar.export"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.label, "Eksportuj (4)")
        button.click()
        XCTAssertTrue(element(app, "sheet.export").waitForExistence(timeout: 5))
    }

    /// Confirms the export and closes the sheet after it finishes.
    @MainActor
    private func exportAndClose(_ app: XCUIApplication) {
        app.buttons["sheet.export.confirm"].click()
        let close = app.buttons["sheet.export.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        close.click()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(app, "sheet.export"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "label \(label)")
    }

    @MainActor
    func testConfirmShowsSummaryForFixture() throws {
        let app = try launch()
        openSheet(app)

        XCTAssertEqual(element(app, "sheet.export.title").text, "Eksportuj do Album/")
        XCTAssertEqual(element(app, "sheet.export.summary").text, "4 nowe, 0 do aktualizacji")
        XCTAssertEqual(element(app, "sheet.export.new").text, "4")
        XCTAssertEqual(element(app, "sheet.export.updated").text, "0")
        XCTAssertEqual(element(app, "sheet.export.skipped").text, "Pominięte: 0 w Ciemni, 1 tylko RAW.")
        XCTAssertFalse(element(app, "sheet.export.conflicts").exists)
        XCTAssertTrue(element(app, "sheet.export.note").text.hasPrefix("Eksport niczego z Album/ nie usuwa."))
    }

    @MainActor
    func testExportWritesOnlyExpectedJpegsAndSecondExportIsDisabled() throws {
        let app = try launch()
        openSheet(app)
        exportAndClose(app)

        let album = try XCTUnwrap(fixture).url.appendingPathComponent("Album")
        let names = try FileManager.default.contentsOfDirectory(atPath: album.path).sorted()
        XCTAssertEqual(names, ["DSC00001.JPG", "DSC00002.JPG", "DSC00003.JPG", "DSC00004.JPG"])

        let button = app.buttons["toolbar.export"]
        waitForLabel(button, "Eksportuj (0)")
        XCTAssertFalse(button.isEnabled)
    }

    @MainActor
    func testChangingOneEditAfterExportGivesOnePending() throws {
        let app = try launch()
        openSheet(app)
        exportAndClose(app)
        waitForLabel(app.buttons["toolbar.export"], "Eksportuj (0)")

        app.typeKey("e", modifierFlags: [])
        let slider = element(app, "edit.temperature")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.8)

        waitForLabel(app.buttons["toolbar.export"], "Eksportuj (1)")
    }
}

private extension XCUIElement {
    var text: String { (value as? String) ?? label }
}
