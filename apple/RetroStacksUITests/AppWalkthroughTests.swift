import XCTest

// Not `@testable import RetroStacks` — same reason as `NavigationTests`: this
// is a separate process that drives the app, it doesn't link against it.
// These literals must match `AccessibilityID` in
// RetroStacks/App/AccessibilityID.swift by hand.

/// Drives the app for `Scripts/leak-check.sh` — see `BACKLOG.md`'s "Automated
/// leak testing" section for the full plan this is phase 2 of.
///
/// Unlike `NavigationTests`, this does **not** call `app.launch()`. It attaches
/// to whatever instance of RetroStacks is already running (launched externally
/// by the leak-check script, with `xctrace --instrument Leaks` already attached
/// to that same process) — `XCUIApplication(bundleIdentifier:)` supports this
/// directly. Splitting "launch + attach the profiler" from "drive the UI" is
/// what lets both target the same process without fighting over who starts it.
///
/// Coverage is deliberately a loop, run twice: a single visit to a screen
/// rarely reveals a retain cycle, but visiting, leaving, and confirming the
/// second pass looks the same as the first is the actual test. Extend this as
/// more of `BACKLOG.md`'s Accessibility path lands — every screen it can reach
/// needs identifiers on its interactive elements first (Phase 1 of that path).
final class AppWalkthroughTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkThroughCoreScreensTwice() throws {
        let app = XCUIApplication(bundleIdentifier: "com.levidahlstrom.RetroStacks")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10),
                      "expected RetroStacks to already be running and foreground — launch it externally first")

        for pass in 1...2 {
            walkOnce(app, pass: pass)
        }
    }

    @MainActor
    private func walkOnce(_ app: XCUIApplication, pass: Int) {
        // Dashboard -> My Collection via the Owned Items tile.
        element(app, "dashboard.ownedItemsTile").tap()
        XCTAssertTrue(app.windows["My Collection"].waitForExistence(timeout: 5), "pass \(pass): Owned Items -> My Collection")

        // Flip the grouping toggle both ways.
        app.radioButtons["All Games"].tap()
        app.radioButtons["By System"].tap()

        // Back to Dashboard, then into a system via the breakdown chart.
        element(app, "sidebar.dashboard").tap()
        XCTAssertTrue(app.windows["Dashboard"].waitForExistence(timeout: 5), "pass \(pass): sidebar -> Dashboard")

        element(app, "dashboard.breakdownRow.snes").tap()
        XCTAssertTrue(app.windows["Super Nintendo Entertainment System"].waitForExistence(timeout: 5),
                      "pass \(pass): breakdown row -> system screen")

        // Exercise the scope picker and the About disclosure.
        for scope in ["Wanted", "Missing", "All", "Owned"] {
            app.radioButtons[scope].tap()
        }
        if app.disclosureTriangles["About SNES"].exists {
            app.disclosureTriangles["About SNES"].tap()
            app.disclosureTriangles["About SNES"].tap()
        }

        // Wishlist and Catalog, then back to Dashboard to close the loop.
        element(app, "sidebar.wishlist").tap()
        XCTAssertTrue(app.windows["Wishlist"].waitForExistence(timeout: 5), "pass \(pass): sidebar -> Wishlist")

        element(app, "sidebar.catalog").tap()
        XCTAssertTrue(app.windows["Catalog"].waitForExistence(timeout: 5), "pass \(pass): sidebar -> Catalog")

        element(app, "sidebar.dashboard").tap()
        XCTAssertTrue(app.windows["Dashboard"].waitForExistence(timeout: 5), "pass \(pass): sidebar -> Dashboard (loop close)")
    }

    /// Matches by `.accessibilityIdentifier` without assuming a specific
    /// XCUIElementType — SwiftUI's chosen role for a given control isn't
    /// always what you'd guess (a `NavigationLink` reads as `.button`, a
    /// `DisclosureGroup` label as `.disclosureTriangle`; discovered by reading
    /// accessibility-hierarchy dumps during this session, not by assumption).
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
