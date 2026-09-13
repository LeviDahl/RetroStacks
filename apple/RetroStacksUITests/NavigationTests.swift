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

/// A **ratchet**, not a zero-tolerance gate: fails if Dashboard's finding
/// count goes *above* `knownFindingBaseline`, but doesn't yet require zero.
///
/// 2026-09-13: this started at 13 findings, all logged+attached but never
/// failing (the app had close to zero accessibility work done). Investigated
/// every one with `.detailedDescription` (not just `.compactDescription`,
/// which was too vague to act on — "[type] Contrast failed" with no element)
/// and fixed what real evidence supported: two Dynamic-Type clipping issues
/// (`StatTile`'s footnote had `.lineLimit(1)` with nothing to shrink it —
/// added `.minimumScaleFactor`) and the `.green`/`.red`/`.yellow` semantic
/// colors' well-documented WCAG light-mode contrast failure (see
/// `Badges.swift`'s `Color.accentGold`/`.accentGreen`/`.accentRed` comment).
/// That took it to 10. The remaining 10 split into two groups, left
/// unresolved on purpose rather than guessed at further:
/// - 3 hard "Contrast failed" findings, all inside `PlatformBreakdownCard`/
///   `BreakdownBar` ("Breakdown by Platform", "$540", "SNES") — survived
///   switching their text to explicit `.primary`, which rules out a simple
///   wrong-color-choice explanation. Best-evidenced remaining theory:
///   `.primary` text sitting close to a long, bright, saturated capsule bar
///   (SNES has the longest bar in the sample data) genuinely washes out
///   regardless of the text's own color — a structural/spacing question, not
///   a colorimetric one, and needs a real visual iteration pass (screenshot,
///   adjust, recheck) that wasn't practical blind this session.
/// - 7 "nearly passed" warnings (`.secondary` text at `.caption` size —
///   passes the 3:1 large-text/UI-component floor, not the full 4.5:1 for
///   small normal text) — this is the *default* look of `.secondary` +
///   `.caption` used throughout the whole app (StatTile titles/footnotes,
///   and almost certainly the same combo elsewhere), not a Dashboard-only
///   bug. Fixing it for real means a deliberate call on how muted "secondary"
///   text should read app-wide — a design decision, not something to change
///   unilaterally while chasing one screen's audit count.
///
/// Lower `knownFindingBaseline` as items above get fixed for real (verified,
/// not guessed) — that's what keeps this a ratchet instead of a ceiling.
final class AccessibilityAuditTests: XCTestCase {
    /// Real, currently-known finding count for Dashboard — see the type doc
    /// comment for exactly what these are and why they're not zero yet.
    static let knownFindingBaseline = 10

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
            // `.compactDescription` alone was just "[type] Contrast failed" —
            // not enough to act on. `.detailedDescription` carries the actual
            // ratio/colors for contrast issues and the frame for clipping;
            // `.element`'s identifier/label says *what* failed.
            let elementInfo = issue.element.map { "element: \($0.identifier.isEmpty ? $0.label : $0.identifier)" } ?? "element: <none>"
            findings.append("[\(issue.auditType)] \(elementInfo)\n  \(issue.detailedDescription)")
            return true // always "handled" at the API level — the assertion below is what actually gates this.
        }

        let report = findings.isEmpty
            ? "No accessibility audit findings on Dashboard."
            : "\(findings.count) accessibility audit finding(s) on Dashboard:\n" + findings.joined(separator: "\n")
        print(report)

        let attachment = XCTAttachment(string: report)
        attachment.name = "Accessibility Audit — Dashboard"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertLessThanOrEqual(
            findings.count, Self.knownFindingBaseline,
            "New accessibility finding(s) on Dashboard — see the attached report. "
                + "If this is a real fix bringing the count down, lower knownFindingBaseline to match."
        )
    }
}
