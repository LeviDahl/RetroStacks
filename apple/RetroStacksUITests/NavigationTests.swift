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

        // The screen's own title (from SystemGamesList's .navigationTitle) is
        // what a real user actually sees, and — unlike an arbitrary label —
        // isn't sensitive to which accessibility role SwiftUI happens to
        // expose a given control as (a DisclosureTriangle for "About SNES"
        // here, a RadioButton for "By System" below; discovered by reading the
        // XCUITest failure's attached accessibility-hierarchy dump).
        //
        // `waitForScreen`, not `app.windows[title]` directly: macOS's split
        // layout gives pushed content its own titled NSWindow, but iOS's
        // tab/stack layout never creates a second window — confirmed 2026-09-14
        // running this exact test on iOS for the first time, where the bare
        // `app.windows[title]` form failed outright. See `waitForScreen`'s doc
        // comment (below, shared with the *AccessibilityAuditTests classes).
        XCTAssertTrue(waitForScreen("Super Nintendo Entertainment System", in: app),
                      "tapping the SNES breakdown row should open the SNES system screen")
    }

    /// Same bug class, different Dashboard link: the "Owned Items" stat tile.
    @MainActor
    func testDashboardOwnedItemsTileNavigatesToCollection() throws {
        let app = launchedApp()

        let ownedItems = app.buttons["dashboard.ownedItemsTile"]
        XCTAssertTrue(ownedItems.waitForExistence(timeout: 5))
        ownedItems.tap()

        XCTAssertTrue(waitForScreen("My Collection", in: app),
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
///   `BreakdownBar` ("Breakdown by Platform", "$540", "SNES") — survived two
///   real, verified attempts, not guesses:
///   1. Switching their text to explicit `.primary` (still failed).
///   2. 2026-09-14: found and fixed a genuine, separate bug where
///      "Breakdown by Platform"'s `Label(...)` rendered visibly lighter than
///      a plain `Text` at the same `.foregroundStyle(.primary)` — confirmed
///      by sampling real screenshot pixels (darkest ink ~(95,95,95) before,
///      ~(15,15,15), true near-black, after switching to a manual icon+text
///      `HStack`). The audit's finding on this exact text **did not change**
///      — still "Contrast failed" at genuinely near-black ink. That rules
///      out literal rendered-pixel-color as the audit's actual mechanism
///      here, which also means the old "bright bar washes out text" theory
///      never actually explained it either (this header sits nowhere near a
///      bar). Root cause still genuinely open — worth checking whether it's
///      about `GeometryReader`-based custom controls specifically, or a
///      larger-Dynamic-Type-size rendering the audit checks but a screenshot
///      at the current size can't show.
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
///
/// 2026-09-14: fixed a real, separate bug found via the hierarchy-dump
/// technique (not an audit finding — `performAccessibilityAudit` doesn't
/// catch missing nav titles): navigating here on iOS-compact never exposed
/// "Catalog" as the navigation bar's own accessible title (the bar's only
/// child was a blank-label `StaticText`). Root cause: `CatalogSection.body`
/// applied `.navigationTitle` to the *outer* `NavigationSplitView`, not to
/// the visible column — on iOS-compact, where the split view collapses to a
/// single column, a title on the outer container never propagates to
/// whichever column is actually shown. `CollectionSection`'s plain
/// `NavigationStack` never had this problem since there's no collapse
/// behavior to lose the title across. Fixed by moving `.navigationTitle` (and
/// `.searchable`/`.toolbar`, which belong with it) onto `contentColumn`
/// directly. Verified for real: `waitForScreen("Catalog", in: app)` below now
/// passes, where it used to need a content-based workaround.
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
        XCTAssertTrue(waitForScreen("Catalog", in: app))

        let findings = try recordAccessibilityAudit(app: app, screenName: "CatalogSection", on: self)
        XCTAssertLessThanOrEqual(
            findings.count, Self.knownFindingBaseline,
            "New accessibility finding(s) on CatalogSection — see the attached report. "
                + "If this is a real fix bringing the count down, lower knownFindingBaseline to match."
        )
    }
}

/// `AddToCollectionFlow`, reached the same way a real user does: "Add Item" on
/// the My Collection toolbar. Audited against the default platform-picker
/// list (`platformList`) — the barcode scanner and the flat search-results
/// list are separate sub-screens, not covered by this one audit pass.
///
/// 2026-09-14: 10 findings, none fixed yet:
/// - 8 are the same systemic `.mutedText`/`.caption` contrast pattern already
///   documented on Dashboard/SystemGamesList/CollectionSection/CatalogSection
///   (`CatalogPlatformRow`'s "N catalog entries" subtitle) — a deliberate,
///   already-centralized design decision (see `MutedTextStyle`), not new.
/// - 1 is the toolbar "Done" button flagged for Dynamic Type ("User will not
///   be able to change the font size…") — plain `Button("Done") { dismiss() }`
///   with no explicit font override, so there's nothing obvious to fix; likely
///   the same class of SwiftUI-internal audit quirk as the `Label` and
///   `NavigationLink` cases elsewhere in this file, not chased further this
///   pass.
/// - 1 is a genuine outlier worth remembering: "Sega Dreamcast" (a plain
///   `Text(platform.name)`, default `.primary` styling, no muted text
///   involved) hard-"Contrast failed" while every other platform row didn't —
///   same shape as `CollectionSectionAccessibilityAuditTests`'s single
///   Nintendo GameCube anomaly. Not investigated further this pass for the
///   same reason: two independent pixel-sampling investigations elsewhere
///   this session (`BreakdownBar` header, badge colors) already showed the
///   audit's "Contrast failed" doesn't reliably track actual rendered pixel
///   color, so chasing one more single-row anomaly without new evidence isn't
///   a good use of time.
final class AddToCollectionFlowAccessibilityAuditTests: XCTestCase {
    static let knownFindingBaseline = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddToCollectionFlowAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        navigateToSection(sidebarID: "sidebar.collection", tabTitle: "Collection", in: app)
        XCTAssertTrue(waitForScreen("My Collection", in: app))

        let addButton = app.buttons["Add Item"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(waitForScreen("Add to Collection", in: app))

        let findings = try recordAccessibilityAudit(app: app, screenName: "AddToCollectionFlow", on: self)
        XCTAssertLessThanOrEqual(
            findings.count, Self.knownFindingBaseline,
            "New accessibility finding(s) on AddToCollectionFlow — see the attached report. "
                + "If this is a real fix bringing the count down, lower knownFindingBaseline to match."
        )
    }
}

/// `SidebarView` — macOS/iPad-regular-width only (`RootView.layout` falls back
/// to `tabLayout` on iOS-compact, where this view never mounts at all). Must
/// be run against a **regular-width** destination:
/// `xcodebuild ... -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:RetroStacksUITests/SidebarViewAccessibilityAuditTests test`
/// — the standard iPhone 17 destination this suite otherwise uses is
/// compact-width and will fail `waitForScreen` immediately since the sidebar
/// never appears. (A real macOS run would also work in principle, but
/// macOS-hosted XCUITest needs a real, unlocked interactive login session to
/// inject synthetic events — it hangs indefinitely headless; the iPad
/// Simulator destination has no such requirement.)
///
/// 2026-09-14: unlike every other screen in this file, `RootView.splitLayout`
/// means the sidebar is *never* shown alone on a regular-width destination —
/// whatever's in the detail pane (Dashboard, by default) is on screen at the
/// same time, and `performAccessibilityAudit` audits everything currently
/// visible, not one view's subtree. A first pass came back with 67 raw
/// findings, the large majority Dashboard content ("GoldenEye 007", "N64",
/// "Total Invested", …) already covered by `AccessibilityAuditTests`
/// (Dashboard) above — counting those here too would double-count and drift
/// out of sync with that screen's own baseline. Scoped down to just the 4
/// `sidebar.<section>`-identified rows instead (filtering `findings` by
/// element identifier below), which is the only part of the screen this class
/// actually owns.
///
/// That gives **8 real, consistent findings**: every one of the 4 sidebar
/// rows (Dashboard/Collection/Wishlist/Catalog) — not just the selected
/// one — hard-fails both "Contrast failed" and "may be clipped at larger
/// Dynamic Type sizes". `row(_:badge:)` builds each with a plain
/// `Label(section.title, systemImage: section.symbol)` inside a stock
/// `List(selection:)` + `.listStyle(.sidebar)` — about as default as SwiftUI
/// gets, so unlike the single-row anomalies elsewhere in this file (Nintendo
/// GameCube in `CollectionSectionAccessibilityAuditTests`, Sega Dreamcast in
/// `AddToCollectionFlowAccessibilityAuditTests`) this is systemic across
/// every row, not an outlier. Worth a real look later, but not chased via
/// pixel-sampling this pass: two separate investigations elsewhere this
/// session (`BreakdownBar`'s header, the badge colors in `Badges.swift`)
/// already showed this audit's "Contrast failed" doesn't reliably track
/// actual rendered pixel color, so a third blind attempt isn't a good use of
/// time without first understanding what the audit actually measures.
final class SidebarViewAccessibilityAuditTests: XCTestCase {
    static let knownFindingBaseline = 8

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarViewAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(waitForScreen("RetroStacks", in: app), "expected the sidebar's own nav title on a regular-width destination")

        let allFindings = try recordAccessibilityAudit(app: app, screenName: "SidebarView", on: self)
        // The detail pane (Dashboard by default) is on screen at the same time on a
        // regular-width destination — scope to just the 4 `sidebar.*`-identified rows
        // this screen actually owns, not the detail pane's own findings (already
        // tracked separately by AccessibilityAuditTests, above).
        let findings = allFindings.filter { $0.contains("element: sidebar.") }
        XCTAssertLessThanOrEqual(
            findings.count, Self.knownFindingBaseline,
            "New accessibility finding(s) on SidebarView's own rows — see the attached report (full screen, filter for \"sidebar.\"). "
                + "If this is a real fix bringing the count down, lower knownFindingBaseline to match."
        )
    }
}
