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

/// Waits for the screen titled `title` to be on screen. macOS's split layout
/// gives pushed content its own titled `NSWindow` (`app.windows[title]`, the
/// pattern the rest of this file and `AppWalkthroughTests` use) — but iOS's
/// tab/stack layout (`RootView.tabLayout`, compact width) never creates a
/// second window, so the navigation bar's own title is the closest
/// equivalent there.
@MainActor
private func waitForScreen(_ title: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
    #if os(macOS)
    return app.windows[title].waitForExistence(timeout: timeout)
    #else
    return app.navigationBars[title].waitForExistence(timeout: timeout)
    #endif
}

/// Taps into a top-level section. macOS/iPad-regular-width gets `SidebarView`
/// (`sidebar.<AppSection rawValue>` identifiers); iPhone-compact-width gets
/// `RootView.tabLayout`'s tab bar instead, labelled by `AppSection.tabTitle`
/// — there's no shared identifier between the two, so the caller passes both.
@MainActor
private func navigateToSection(sidebarID: String, tabTitle: String, in app: XCUIApplication) {
    #if os(macOS)
    let sidebarItem = app.buttons[sidebarID]
    XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5), "expected a sidebar row for \(sidebarID)")
    sidebarItem.tap()
    #else
    let tabItem = app.tabBars.buttons[tabTitle]
    XCTAssertTrue(tabItem.waitForExistence(timeout: 5), "expected a \(tabTitle) tab")
    tabItem.tap()
    #endif
}

/// Shared by every `*AccessibilityAuditTests` class below — runs the audit
/// against whatever's currently on screen, attaches a readable report, and
/// hands back the findings for the caller to ratchet against its own
/// `knownFindingBaseline`. See `AccessibilityAuditTests` (Dashboard, above)
/// for why `.detailedDescription` + `.element` instead of just
/// `.compactDescription`, and why this is a ratchet, not a zero-tolerance gate.
@MainActor
private func recordAccessibilityAudit(app: XCUIApplication, screenName: String, on testCase: XCTestCase) throws -> [String] {
    var findings: [String] = []
    try app.performAccessibilityAudit { issue in
        let elementInfo = issue.element.map { "element: \($0.identifier.isEmpty ? $0.label : $0.identifier)" } ?? "element: <none>"
        findings.append("[\(issue.auditType)] \(elementInfo)\n  \(issue.detailedDescription)")
        return true // always "handled" at the API level — the caller's assertion is what actually gates this.
    }

    let report = findings.isEmpty
        ? "No accessibility audit findings on \(screenName)."
        : "\(findings.count) accessibility audit finding(s) on \(screenName):\n" + findings.joined(separator: "\n")
    print(report)

    let attachment = XCTAttachment(string: report)
    attachment.name = "Accessibility Audit — \(screenName)"
    attachment.lifetime = .keepAlways
    testCase.add(attachment)

    return findings
}

/// SystemGamesList, reached the same way `NavigationTests` reaches it: tap
/// the SNES row in Dashboard's platform breakdown.
///
/// 2026-09-13: 52 findings, none fixed yet — see BACKLOG.md's Accessibility
/// section for the breakdown (short version: the same `.secondary`+`.caption`
/// pattern `AccessibilityAuditTests`'s doc comment already flagged as an
/// app-wide styling decision, now confirmed to recur here at much higher
/// volume because every game row repeats it, plus a `CompletenessBadge`
/// tinted-capsule contrast question that needs real visual iteration, not
/// guessed at blind).
final class SystemGamesListAccessibilityAuditTests: XCTestCase {
    static let knownFindingBaseline = 52

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSystemGamesListAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let snesRow = app.buttons["dashboard.breakdownRow.snes"]
        XCTAssertTrue(snesRow.waitForExistence(timeout: 5))
        snesRow.tap()
        XCTAssertTrue(waitForScreen("Super Nintendo Entertainment System", in: app))

        let findings = try recordAccessibilityAudit(app: app, screenName: "SystemGamesList (SNES)", on: self)
        XCTAssertLessThanOrEqual(
            findings.count, Self.knownFindingBaseline,
            "New accessibility finding(s) on SystemGamesList — see the attached report. "
                + "If this is a real fix bringing the count down, lower knownFindingBaseline to match."
        )
    }
}

/// CollectionSection ("My Collection"), reached via the sidebar.
///
/// 2026-09-13: 26 findings, none fixed yet — same systemic `.secondary`/
/// `.caption` pattern as `SystemGamesListAccessibilityAuditTests` (per-system
/// summary rows: item counts, percentages, dollar amounts). One thing worth a
/// closer look later: most rows only "not high enough unless font size is
/// larger" (a soft warning), but one specific row (Nintendo GameCube) hard
/// "Contrast failed" on the exact same fields — possibly a selection/hover
/// highlight background making an otherwise-borderline color actually fail;
/// not investigated further this pass.
final class CollectionSectionAccessibilityAuditTests: XCTestCase {
    static let knownFindingBaseline = 26

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCollectionSectionAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        navigateToSection(sidebarID: "sidebar.collection", tabTitle: "Collection", in: app)
        XCTAssertTrue(waitForScreen("My Collection", in: app))

        let findings = try recordAccessibilityAudit(app: app, screenName: "CollectionSection", on: self)
        XCTAssertLessThanOrEqual(
            findings.count, Self.knownFindingBaseline,
            "New accessibility finding(s) on CollectionSection — see the attached report. "
                + "If this is a real fix bringing the count down, lower knownFindingBaseline to match."
        )
    }
}

/// CatalogSection ("Catalog" — `navigationTitleText` overrides `AppSection`'s
/// own "Browse Catalog" sidebar label when no platform filter is active).
///
/// 2026-09-13: 11 findings, none fixed yet — mostly the same systemic
/// `.secondary` contrast pattern, at much lower volume here since this
/// screen's default view is just a flat platform list, not per-item detail.
/// Separately (not counted as an audit finding, `performAccessibilityAudit`
/// doesn't catch it): navigating here on iOS-compact never exposes "Catalog"
/// as the navigation bar's own accessible title — confirmed via a raw
/// accessibility-hierarchy dump, the bar's only child is a blank-label
/// `StaticText`. `CatalogSection` nests its own `NavigationSplitView` inside
/// `RootView`'s tab; `CollectionSection` doesn't and its title *does* expose
/// correctly, so the nesting is the likely cause. Worth a real VoiceOver
/// check — logged in BACKLOG.md rather than guessed at here.
final class CatalogSectionAccessibilityAuditTests: XCTestCase {
    static let knownFindingBaseline = 11

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCatalogSectionAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        navigateToSection(sidebarID: "sidebar.catalog", tabTitle: "Catalog", in: app)
        // Not `waitForScreen`: CatalogSection nests its own NavigationSplitView
        // inside RootView's tab, and on iOS-compact that inner split view's
        // collapsed NavigationStack never exposes "Catalog" as the navigation
        // bar's accessible title (confirmed via the accessibility hierarchy
        // dump — the bar's only child is a StaticText with a blank label).
        // That's arguably its own accessibility finding, but out of scope
        // here; a known platform row is a reliable proxy that we're on-screen.
        XCTAssertTrue(app.buttons["Nintendo Entertainment System, 7 catalog entries"].waitForExistence(timeout: 5))

        let findings = try recordAccessibilityAudit(app: app, screenName: "CatalogSection", on: self)
        XCTAssertLessThanOrEqual(
            findings.count, Self.knownFindingBaseline,
            "New accessibility finding(s) on CatalogSection — see the attached report. "
                + "If this is a real fix bringing the count down, lower knownFindingBaseline to match."
        )
    }
}
