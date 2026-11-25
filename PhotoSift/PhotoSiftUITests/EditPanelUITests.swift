import PhotoSiftTestSupport
import XCTest

final class EditPanelUITests: XCTestCase {
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

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func waitForXMP(_ id: String) throws -> String {
        let url = try XCTUnwrap(fixture).url.appendingPathComponent("\(id).xmp")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8), text.contains("photosift") { return text }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("No XMP with photosift fields for \(id)")
        return ""
    }

    @MainActor
    func testEOpensPanelAndDReturns() throws {
        let app = try launch(.init(pairs: ["DSC00001"]))
        XCTAssertFalse(element(app, "edit.panel").exists)
        app.typeKey("e", modifierFlags: [])
        XCTAssertTrue(element(app, "edit.panel").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "edit.temperature").exists)
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(element(app, "edit.angle").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "edit.orientation.landscape").exists)
        app.typeKey("d", modifierFlags: [])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(app, "edit.panel"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    /// Regression: with an untouched crop, R then E (and E then R) used to leave the stage empty.
    @MainActor
    func testSwitchingBetweenCropAndColourToolsKeepsPhotoVisible() throws {
        let app = try launch(.init(pairs: ["DSC00001"]))
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(element(app, "crop.overlay").waitForExistence(timeout: 5))
        expectStageImage(app)
        app.typeKey("e", modifierFlags: [])
        XCTAssertTrue(element(app, "edit.panel").waitForExistence(timeout: 5))
        expectStageImage(app)
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(element(app, "crop.overlay").waitForExistence(timeout: 5))
        expectStageImage(app)
    }

    /// The edit stage must contain a drawn photo: an image element with a non-zero size.
    @MainActor
    private func expectStageImage(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let image = element(app, "edit.image")
        XCTAssertTrue(image.waitForExistence(timeout: 5), "no edit.image", file: file, line: line)
        XCTAssertGreaterThan(image.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(image.frame.height, 0, file: file, line: line)
    }

    @MainActor
    func testTemperatureChangeWritesXMP() throws {
        let app = try launch(.init(pairs: ["DSC00001"]))
        app.typeKey("e", modifierFlags: [])
        let slider = element(app, "edit.temperature")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertNotEqual(element(app, "edit.temperature.value").text, "0")
        let xmp = try waitForXMP("DSC00001")
        XCTAssertTrue(xmp.contains("photosift"))
    }

    @MainActor
    func testUndoAndRedoOfTemperatureChange() throws {
        let app = try launch(.init(pairs: ["DSC00001"]))
        app.typeKey("e", modifierFlags: [])
        let slider = element(app, "edit.temperature")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let original = element(app, "edit.temperature.value").text
        slider.adjust(toNormalizedSliderPosition: 0.8)
        let changed = element(app, "edit.temperature.value").text
        XCTAssertNotEqual(changed, original)
        _ = try waitForXMP("DSC00001")

        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(element(app, "edit.temperature.value").text, original)
        let xmpURL = try XCTUnwrap(fixture).url.appendingPathComponent("DSC00001.xmp")
        try waitUntil { !((try? String(contentsOf: xmpURL, encoding: .utf8)) ?? "").contains("photosift:temperature") }

        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(element(app, "edit.temperature.value").text, changed)
        try waitUntil { ((try? String(contentsOf: xmpURL, encoding: .utf8)) ?? "").contains("photosift:temperature") }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Condition not met within 5 s", file: file, line: line)
    }

    @MainActor
    func testExposureChangeWritesXMP() throws {
        let app = try launch(.init(pairs: ["DSC00001"]))
        app.typeKey("e", modifierFlags: [])
        let slider = element(app, "edit.exposure")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.75)
        XCTAssertNotEqual(element(app, "edit.exposure.value").text, "0 EV")

        let url = try XCTUnwrap(fixture).url.appendingPathComponent("DSC00001.xmp")
        let pattern = try NSRegularExpression(pattern: #"photosift:exposure[^0-9-]+(-?[0-9]+(?:\.[0-9]+)?)"#)
        let deadline = Date().addingTimeInterval(5)
        var exposure: Double?
        while Date() < deadline, exposure.map({ $0 == 0 }) ?? true {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                exposure = Double(text[range])
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertNotNil(exposure, "photosift:exposure missing in the XMP")
        XCTAssertGreaterThan(exposure ?? 0, 0)
    }

    @MainActor
    func testShadowsChangeWritesXMP() throws {
        throw XCTSkip("Suwaki Światła/Cienie ukryte na życzenie użytkownika, kod zostaje na przyszłość")
        let app = try launch(.init(pairs: ["DSC00001"]))
        app.typeKey("e", modifierFlags: [])
        let slider = element(app, "edit.shadows")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.75)
        XCTAssertNotEqual(element(app, "edit.shadows.value").text, "0")

        let url = try XCTUnwrap(fixture).url.appendingPathComponent("DSC00001.xmp")
        let pattern = try NSRegularExpression(pattern: #"photosift:shadows[^0-9-]+(-?[0-9]+(?:\.[0-9]+)?)"#)
        let deadline = Date().addingTimeInterval(5)
        var shadows: Double?
        while Date() < deadline, shadows.map({ $0 == 0 }) ?? true {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                shadows = Double(text[range])
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertNotNil(shadows, "photosift:shadows missing in the XMP")
        XCTAssertNotEqual(shadows ?? 0, 0)
    }

    @MainActor
    func testDarkroomPhotoIsLockedAndUnmarkUnlocks() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        app.typeKey("c", modifierFlags: [])
        app.typeKey("e", modifierFlags: [])
        XCTAssertTrue(element(app, "edit.locked.title").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "edit.locked.title").text, "Edycja zablokowana")
        XCTAssertEqual(
            element(app, "edit.locked.text").text,
            "Zdjęcie jest w Ciemni — obrobisz je w Lightroomie z pliku RAW."
        )
        XCTAssertFalse(element(app, "edit.temperature").exists)
        let unmark = app.buttons["edit.locked.unmark"]
        XCTAssertTrue(unmark.waitForExistence(timeout: 5))
        // Every button inside the `info` scroll view reports isHittable == false to XCUITest (the
        // accessibility container wins the hit point lookup), so click by coordinate.
        unmark.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(element(app, "edit.temperature").waitForExistence(timeout: 5))
    }

    @MainActor
    func testPasteWhiteBalanceMarksThreeGridSelectedPhotosAsEdited() throws {
        let names = ["DSC00001", "DSC00002", "DSC00003", "DSC00004"]
        let app = try launch(.init(pairs: names))
        app.typeKey("e", modifierFlags: [])
        let slider = element(app, "edit.temperature")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.8)
        app.typeKey("c", modifierFlags: [.command, .shift])
        app.typeKey("d", modifierFlags: [])
        app.typeKey("g", modifierFlags: [])
        XCTAssertTrue(element(app, "screen.grid").waitForExistence(timeout: 5))

        element(app, "grid.cell.DSC00002").click()
        XCUIElement.perform(withKeyModifiers: .command) {
            element(app, "grid.cell.DSC00003").click()
            element(app, "grid.cell.DSC00004").click()
        }
        app.typeKey("v", modifierFlags: [.command, .shift])

        for name in ["DSC00002", "DSC00003", "DSC00004"] {
            let cell = element(app, "grid.cell.\(name)")
            let edited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'edytowane'"), object: cell)
            XCTAssertEqual(XCTWaiter.wait(for: [edited], timeout: 5), .completed, name)
        }
    }
}

private extension XCUIElement {
    var text: String { (value as? String) ?? label }
}
