import XCTest

// Not `@testable import RetroStacks`: the UI test runner is a separate app
// process from RetroStacks.app (it drives it via XCUIApplication, it doesn't
// link against it), so app-module symbols aren't available here — only
// XCUITest unit tests (RetroStacksTests) can share Swift types that way.
// These literals must match `AccessibilityID` in
// RetroStacks/App/AccessibilityID.swift by hand.

/// Regression coverage for the class of bug that shipped 2026-09-12: a
/// `NavigationLink` inside `DashboardView` was dead on macOS/iPadOS because
/// Dashboard didn't own its own `NavigationStack` — placed directly in
/// `NavigationSplitView`'s detail column, the link tried to push a column past
/// detail, which doesn't exist, and failed with only a console log to show for
/// it ("There is no next column after the detail column"). That's a rendering /
/// navigation-composition bug — nothing a unit test can see, since it only
/// exists once real views are actually hosted and pushed. A UI test is the
/// right (and only) tool for it.
///
/// Every case launches with `-uiTesting` (see `RetroStacksApp.isUITesting`) so
/// each run gets a fresh in-memory store seeded from `SampleData` — no real
/// network sync, nothing left over from a previous run.
final class NavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        return app
    }

    /// The exact bug: tapping a platform in the Dashboard's "Breakdown by
    /// Platform" chart didn't navigate anywhere on macOS. The seed data
    /// (`Resources/SampleCollection.json`) owns SNES items, so the row exists
    /// on a fresh launch with no setup.
    ///
    /// Queries by `.accessibilityIdentifier`, not visible text: SwiftUI
    /// collapses a `NavigationLink`'s child `Text` into one opaque
    /// accessibility element, so `app.staticTexts["SNES"]` never exists to
    /// find — same root cause as the accessibility audit's "Parent/Child
    /// mismatch" finding on this screen.
    @MainActor
    func testDashboardBreakdownRowNavigatesToSystemScreen() throws {
        let app = launchedApp()

        let snesRow = app.buttons["dashboard.breakdownRow.snes"]
        XCTAssertTrue(snesRow.waitForExistence(timeout: 5), "expected a SNES row in the platform breakdown")
        snesRow.tap()

        // The window's own title (from SystemGamesList's .navigationTitle) is
        // what a real user actually sees, and — unlike an arbitrary label —
        // isn't sensitive to which accessibility role SwiftUI happens to
        // expose a given control as (a DisclosureTriangle for "About SNES"
        // here, a RadioButton for "By System" below; discovered by reading the
        // XCUITest failure's attached accessibility-hierarchy dump).
        let systemWindow = app.windows["Super Nintendo Entertainment System"]
        XCTAssertTrue(systemWindow.waitForExistence(timeout: 5),
                      "tapping the SNES breakdown row should open the SNES system screen")
    }

    /// Same bug class, different Dashboard link: the "Owned Items" stat tile.
    @MainActor
    func testDashboardOwnedItemsTileNavigatesToCollection() throws {
        let app = launchedApp()

        let ownedItems = app.buttons["dashboard.ownedItemsTile"]
        XCTAssertTrue(ownedItems.waitForExistence(timeout: 5))
        ownedItems.tap()

        let collectionWindow = app.windows["My Collection"]
        XCTAssertTrue(collectionWindow.waitForExistence(timeout: 5),
                      "tapping Owned Items should switch to My Collection")
    }
}

/// Not a regression test — a standing accessibility check, run every time this
/// suite runs. Deliberately **non-failing for now**: the app currently has
/// close to zero accessibility labels/identifiers (tracked in BACKLOG.md), so
/// a hard-failing audit today would just permanently red the pipeline instead
/// of being useful. The issue handler logs and attaches every finding instead
/// of throwing. Once the accessibility-identifiers backlog item lands, tighten
/// this: fail on `.sufficientElementDescription` / `.contrast` findings at
/// minimum, and narrow or drop the always-true issueHandler.
final class AccessibilityAuditTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDashboardAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 5))

        var findings: [String] = []
        try app.performAccessibilityAudit { issue in
            findings.append("[\(issue.auditType)] \(issue.compactDescription)")
            return true // handled — never fails this test; see the doc comment above.
        }

        let report = findings.isEmpty
            ? "No accessibility audit findings on Dashboard."
            : "\(findings.count) accessibility audit finding(s) on Dashboard:\n" + findings.joined(separator: "\n")
        print(report)

        let attachment = XCTAttachment(string: report)
        attachment.name = "Accessibility Audit — Dashboard"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
