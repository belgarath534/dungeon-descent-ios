import XCTest

/// Makes characters through all twelve creation steps, the way a player
/// does, then starts a run with one. Run on an iPad by the "Screen tour"
/// workflow (test: create) after an iPad player's game kept closing before
/// character creation finished. A crash fails the test, and the workflow
/// keeps the crash report.
final class CreateCharacterTest: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Not Now", "Cancel", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    /// The largest accessibility text size (an iPad player uses one of the
    /// Larger Text sizes), so every screen is laid out the way theirs is.
    private let bigText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    func testCreateCharactersAndPlay() {
        for round in 0..<4 {
            app.launchArguments = ["-skipLoading", "-startScreen", "charlist"]
            app.launch()
            sleep(4)
            dismissPopups()
            shot("round\(round)-charlist")
            let create = button("Create a new character")
            XCTAssert(waitFor(create), "No Create a new character button (round \(round))")
            create.tap()
            sleep(2)
            makeCharacter(round: round)
            XCTAssertEqual(app.state, .runningForeground, "The game closed during character creation (round \(round))")
            app.terminate()
        }
        // Then play: the first character's dungeon.
        app.launchArguments = ["-skipLoading", "-startScreen", "dungeon"]
        app.launch()
        sleep(6)
        dismissPopups()
        shot("dungeon")
        for i in 0..<30 {
            guard app.state == .runningForeground else { break }
            let buttons = app.buttons.allElementsBoundByIndex.filter { $0.isHittable && !$0.label.isEmpty
                && !["Back", "← Menu", "Menu", "Settings", "Quit", "Abandon"].contains(where: $0.label.contains) }
            guard !buttons.isEmpty else { sleep(1); continue }
            buttons[i % buttons.count].tap()
            usleep(700_000)
            dismissPopups()
        }
        shot("after-play")
        XCTAssertEqual(app.state, .runningForeground, "The game closed while playing")
    }

    /// Steps 1 to 12 and the confirmation. Each round picks differently.
    private func makeCharacter(round: Int) {
        // 1–3: class, race, profession by the ◀ ▶ slider (round + 1 steps along).
        for (slider, next) in [("Next class", "Continue to Race →"), ("Next race", "Continue to Profession →"),
                               ("Next profession", "Continue to Dungeon →")] {
            let arrow = button(slider)
            XCTAssert(waitFor(arrow), "No \(slider) button")
            for _ in 0...(round * 3) { arrow.tap(); usleep(300_000) }
            shot("round\(round)-\(slider)")
            tap(next)
        }
        // 4: the name.
        let field = app.textFields["Enter character name, maximum 24 characters"]
        XCTAssert(waitFor(field), "No name field")
        if round % 2 == 0 {
            field.tap()
            field.typeText("Tester \(round)")
        } else {
            tap("Generate a random fantasy name")
        }
        shot("round\(round)-name")
        tap("Continue to Dungeon →")
        // 5–12: take what's offered, press on.
        for next in ["Continue to Fate →", "Continue to run mode step", "Continue to spirit step", "Continue to corruption step",
                     "Continue to hunter mode step", "Continue to companion guide step", "Continue to origin",
                     round % 2 == 0 ? "Skip backstory and descend now" : "Descend with chosen backstory"] {
            shot("round\(round)-before-\(next)")
            tap(next)
        }
        shot("round\(round)-confirm")
        tap("Confirm and descend")
        sleep(2)
        shot("round\(round)-created")
    }

    /// A button by its label, in any letter case (button styles show some in capitals).
    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    /// Turns the iPad each time, the way it turns in a player's hands, so
    /// every creation screen is rebuilt in portrait and landscape.
    private var turns = 0
    private func turn() {
        let o: [UIDeviceOrientation] = [.landscapeLeft, .portrait, .landscapeRight, .portraitUpsideDown, .portrait]
        XCUIDevice.shared.orientation = o[turns % o.count]
        turns += 1
        usleep(600_000)
        XCTAssertEqual(app.state, .runningForeground, "The game closed when the iPad turned (turn \(turns))")
    }

    private func tap(_ label: String) {
        turn()
        let b = button(label)
        XCTAssert(waitFor(b), "No \"\(label)\" button. The game is \(app.state == .runningForeground ? "open" : "closed").")
        for _ in 0..<6 where !b.isHittable { app.swipeUp() }
        b.tap()
        usleep(900_000)
    }

    private func waitFor(_ e: XCUIElement) -> Bool {
        if e.waitForExistence(timeout: 8) { return true }
        for _ in 0..<6 { app.swipeUp(); if e.exists { return true } }
        return e.exists
    }

    private func dismissPopups() {
        for _ in 0..<4 {
            var closed = false
            for label in ["Continue to the game", "Not now", "OK", "✕ Close", "Close"] {
                let b = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
                if b.exists && b.isHittable { b.tap(); closed = true; sleep(1) }
            }
            if !closed { break }
        }
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
