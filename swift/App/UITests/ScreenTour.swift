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

        visit(prefix: "Play,", name: "02-characters", screen: "Character list")
        visit(prefix: "Endless Descent", name: "03-endless-descent", screen: "Endless Descent")
        visit(prefix: "Bestiary", name: "04-bestiary", screen: "Bestiary")
        visit(prefix: "Quests", name: "05-quests", screen: "Quests")
        visit(prefix: "What's New", name: "06-whats-new", screen: "What's New")
        visit(prefix: "Help", name: "07-help", screen: "Help")
    }

    // MARK: Helpers

    private func launch() {
        app.terminate()
        app.launch()
        sleep(4)
        app.tap() // lets the interruption monitor see any system alert
        dismissPopups()
    }

    /// Start-up pop-ups the game itself shows (What's New, a web save, daily rewards).
    private func dismissPopups() {
        for _ in 0..<4 {
            var closed = false
            for label in ["Continue to the game", "Not now", "OK", "✕ Close", "Close"] {
                let b = app.buttons[label].firstMatch
                if b.exists && b.isHittable { b.tap(); closed = true; sleep(1) }
            }
            if !closed { break }
        }
    }

    private func visit(prefix: String, name: String, screen: String) {
        launch()
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
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
            app.swipeUp()
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
