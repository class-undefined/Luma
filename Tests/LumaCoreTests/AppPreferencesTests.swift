import XCTest
@testable import LumaCore

final class AppPreferencesTests: XCTestCase {
    func testDefaultAndExplicitOpenPolicies() {
        XCTAssertFalse(OpenMode.automatic.opensViewer(singleImage: false))
        XCTAssertTrue(OpenMode.automatic.opensViewer(singleImage: true))
        XCTAssertFalse(OpenMode.browser.opensViewer(singleImage: true))
        XCTAssertTrue(OpenMode.details.opensViewer(singleImage: false))
        XCTAssertTrue(OpenMode.imageOnly.opensViewer(singleImage: false))
        XCTAssertEqual(OpenMode.imageOnly.viewerStyle, .imageOnly)
    }
    func testPreferencesRoundTripAndHandleOlderInstalls() {
        let name = "LumaPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = AppPreferences(defaults: defaults)
        XCTAssertEqual(settings.openMode, .automatic)
        XCTAssertTrue(settings.showFilmstrip)
        settings.openMode = .imageOnly
        settings.restoreLastFolder = false
        settings.loadAdjacentImages = false
        settings.showFilmstrip = false
        settings.showStatusBar = false
        settings.save(to: defaults)
        XCTAssertEqual(AppPreferences(defaults: defaults), settings)
        defaults.set("unsupported-mode", forKey: "openMode")
        XCTAssertEqual(AppPreferences(defaults: defaults).openMode, .automatic)
    }
}
