import PhotoSiftTestSupport
import XCTest

final class DarkroomSheetUITests: XCTestCase {
    /// Throwaway `UserDefaults` suite: the app keeps recents and resume positions here, not in the user\'s defaults.
    private let defaultsSuite = "photosift.uitests.\(UUID().uuidString)"
    private var fixture: FixtureFolder?

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        if let fixture { try? FileManager.default.removeItem(at: fixture.url) }
        fixture = nil
    }

    @MainActor
    private func launch(_ spec: FixtureFolder.Spec, prepare: (URL) throws -> Void = { _ in }) throws -> XCUIApplication {
        let folder = try FixtureFolder.make(spec)
        fixture = folder
        try prepare(folder.url)
        let app = XCUIApplication()
        app.launchArguments = ["--open-folder", folder.url.path, "--defaults-suite", defaultsSuite]
        app.launch()
        XCTAssertTrue(app.windows["Photo Sift"].waitForExistence(timeout: 10))
        return app
    }

    /// Marks the first photo for the Darkroom and opens the sheet from the toolbar.
    @MainActor
    private func openSheet(_ app: XCUIApplication) -> XCUIElement {
        app.typeKey("c", modifierFlags: [])
        let button = app.buttons["toolbar.sendToDarkroom"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.label, "Do Ciemni (1)")
        button.click()
        let sheet = app.descendants(matching: .any)["sheet.darkroom"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        return sheet
    }

    private func exists(_ name: String) -> Bool {
        guard let fixture else { return false }
        return FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent(name).path)
    }

    @MainActor
    func testConfirmMovesRawAndXmpAndKeepsJpeg() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        _ = openSheet(app)

        let text = app.staticTexts["sheet.darkroom.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 2))
        XCTAssertTrue(text.stringValue.contains("Pliki JPEG zostają na miejscu."))
        app.buttons["sheet.darkroom.confirm"].click()

        let darkroom = app.buttons["toolbar.sendToDarkroom"]
        XCTAssertTrue(darkroom.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "label == %@", "Do Ciemni (0)")
        wait(for: [expectation(for: predicate, evaluatedWith: darkroom)], timeout: 10)
        XCTAssertFalse(darkroom.isEnabled)

        XCTAssertTrue(exists("Ciemnia/DSC00001.ARW"))
        XCTAssertFalse(exists("DSC00001.ARW"))
        XCTAssertTrue(exists("DSC00001.JPG"))
        XCTAssertTrue(exists("DSC00002.ARW"))
        // The XMP held only photosift fields (the mark), so Core deletes it after clearing them: none is left behind.
        XCTAssertFalse(exists("DSC00001.xmp"))
        XCTAssertFalse(exists("Ciemnia/DSC00001.xmp"))
    }

    /// An XMP with a foreign field moves with the ARW, minus the photosift fields.
    @MainActor
    func testConfirmMovesXmpWithForeignFieldsWithoutPhotosiftFields() throws {
        let xmp = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\
            <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="3"/>\
            </rdf:RDF></x:xmpmeta>
            """
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"])) { folder in
            try xmp.write(to: folder.appendingPathComponent("DSC00001.xmp"), atomically: true, encoding: .utf8)
        }
        _ = openSheet(app)
        app.buttons["sheet.darkroom.confirm"].click()

        let darkroom = app.buttons["toolbar.sendToDarkroom"]
        let predicate = NSPredicate(format: "label == %@", "Do Ciemni (0)")
        wait(for: [expectation(for: predicate, evaluatedWith: darkroom)], timeout: 10)

        XCTAssertTrue(exists("Ciemnia/DSC00001.ARW"))
        XCTAssertFalse(exists("DSC00001.xmp"))
        XCTAssertTrue(exists("Ciemnia/DSC00001.xmp"))
        let moved = try String(contentsOf: XCTUnwrap(fixture).url.appendingPathComponent("Ciemnia/DSC00001.xmp"), encoding: .utf8)
        XCTAssertTrue(moved.contains("Rating"))
        XCTAssertFalse(moved.contains("photosift"))
    }

    @MainActor
    func testEnterConfirms() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        _ = openSheet(app)
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let darkroom = app.buttons["toolbar.sendToDarkroom"]
        let predicate = NSPredicate(format: "label == %@", "Do Ciemni (0)")
        wait(for: [expectation(for: predicate, evaluatedWith: darkroom)], timeout: 10)
        XCTAssertTrue(exists("Ciemnia/DSC00001.ARW"))
    }

    @MainActor
    func testEscapeCancelsWithoutMoving() throws {
        let app = try launch(.init(pairs: ["DSC00001", "DSC00002"]))
        let sheet = openSheet(app)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)
        XCTAssertEqual(app.buttons["toolbar.sendToDarkroom"].label, "Do Ciemni (1)")
        XCTAssertTrue(exists("DSC00001.ARW"))
        XCTAssertFalse(exists("Ciemnia/DSC00001.ARW"))
    }
}

private extension XCUIElement {
    /// Static text exposes its string as `value` on macOS; `label` is empty.
    var stringValue: String { (value as? String) ?? label }
}
