import XCTest

/// Opens the game on whatever it runs on (iPhone simulator, a Mac running the
/// iPad app, later Vision Pro), visits a few screens, saves a screenshot of
/// each and runs Apple's accessibility audit on it. Nothing here fails on what
/// it finds: the screenshots and the audit's list are the results, saved with
/// the test so the GitHub workflow can upload them.
final class ScreenTour: XCTestCase {
    var app: XCUIApplication!
    var auditReport: [String] = []

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        // Straight to the menu: no five-second loading screen in the screenshots.
        app.launchArguments = ["-skipLoading"]
        // System alerts (notifications, Game Center) are answered "not now".
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Not Now", "Cancel", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    override func tearDown() {
        let report = XCTAttachment(string: auditReport.isEmpty ? "No accessibility issues found." : auditReport.joined(separator: "\n"))
        report.name = "accessibility-audit"
        report.lifetime = .keepAlways
        add(report)
    }

    func testTour() {
        launch()
        shot("01-menu")
        audit("Main menu")
        dumpButtons("menu-buttons")

        // 12.0's tab menu: each screen is in its tab.
        visit(prefix: "Play,", name: "02-characters", screen: "Character list")
        visit(prefix: "Endless Descent", tab: "Play", name: "03-endless-descent", screen: "Endless Descent")
        visit(prefix: "Challenges", tab: "Play", name: "04-challenges", screen: "Challenges")
        visit(prefix: "Battle Pass", tab: "Play", name: "05-battle-pass", screen: "Battle Pass")
        visit(prefix: "Quests", tab: "Play", name: "06-quests", screen: "Quests")
        visit(prefix: "The Spire", tab: "Modes", name: "07-spire", screen: "The Spire")
        visit(prefix: "Co-op", tab: "Multiplayer", name: "08-coop", screen: "Co-op")
        visit(prefix: "Bestiary", tab: "More", name: "09-bestiary", screen: "Bestiary")
        visit(prefix: "Mystery Coin Shop", tab: "More", name: "10-coin-shop", screen: "Coin Shop")
        visit(prefix: "The Chronicles", tab: "More", name: "11-chronicles", screen: "Chronicles")
        visit(prefix: "What's New", tab: "More", name: "12-whats-new", screen: "What's New")
        visit(prefix: "Help", tab: "More", name: "13-help", screen: "Help")
        settings()
    }

    // MARK: Helpers

    private func launch() {
        app.terminate()
        app.launch()
        sleep(4)
        #if !targetEnvironment(macCatalyst) && !os(visionOS)
        app.tap() // lets the interruption monitor see any system alert (iPhone only)
        #endif
        dismissPopups()
    }

    /// Start-up pop-ups the game itself shows (What's New, a web save, daily rewards).
    private func dismissPopups() {
        for _ in 0..<4 {
            var closed = false
            for label in ["Continue to the game", "Not now", "OK", "✕ Close", "Close"] {
                // Button styles show labels in capitals, and so does the accessibility tree.
                let b = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
                if b.exists && b.isHittable { b.tap(); closed = true; sleep(1) }
            }
            if !closed { break }
        }
    }

    /// The tab bar's own button (Play, Modes, Multiplayer, More, Settings).
    private func openTab(_ tab: String) {
        let t = app.tabBars.buttons[tab]
        if t.exists && t.isHittable { t.tap(); sleep(1) }
    }

    private func settings() {
        launch()
        openTab("Settings")
        shot("14-settings")
        audit("Settings")
    }

    private func visit(prefix: String, tab: String? = nil, name: String, screen: String) {
        launch()
        if let tab { openTab(tab) }
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
        guard scrollTo(button) else {
            auditReport.append("[\(screen)] Couldn't find a button starting with \"\(prefix)\".")
            shot(name + "-not-found")
            return
        }
        button.tap()
        sleep(2)
        dismissPopups()
        shot(name)
        audit(screen)
    }

    /// Swipes the menu until the button is on screen.
    private func scrollTo(_ e: XCUIElement) -> Bool {
        for _ in 0..<12 {
            if e.exists && e.isHittable { return true }
            // The visible tab's list: with the tab menu, every tab has its own
            // scroll view and the first one is often a hidden tab's.
            let list = app.scrollViews.allElementsBoundByIndex.first { $0.isHittable }
            if let list { list.swipeUp() } else { app.swipeUp() }
        }
        return e.exists && e.isHittable
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func dumpButtons(_ name: String) {
        let labels = app.buttons.allElementsBoundByIndex.prefix(80).map { $0.label }
        let a = XCTAttachment(string: labels.joined(separator: "\n"))
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func audit(_ screen: String) {
        guard #available(iOS 17.0, *) else { return }
        do {
            try app.performAccessibilityAudit { issue in
                let who = issue.element.map { "\"\($0.label)\" (\($0.elementType.rawValue))" } ?? "screen"
                self.auditReport.append("[\(screen)] \(issue.compactDescription) — \(who). \(issue.detailedDescription)")
                return true // record it, don't fail
            }
        } catch {
            auditReport.append("[\(screen)] Audit couldn't run: \(error.localizedDescription)")
        }
    }
}
