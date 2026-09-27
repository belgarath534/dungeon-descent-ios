import UIKit
import Capacitor

// Magic Tap (VoiceOver's two-finger double-tap) is intercepted above the
// WebView, at the UIResponder level — it's not something a web page can
// hook into on its own, unlike a Rotor custom action tied to a specific
// focused element. This makes it genuinely global: works the same
// regardless of what's currently focused, which is exactly why it's the
// right fit for something like Echo-Location that the player should be
// able to trigger from anywhere while exploring.
class MainViewController: CAPBridgeViewController {
    override func accessibilityPerformMagicTap() -> Bool {
        webView?.evaluateJavaScript("if (typeof echoLocate === 'function') { echoLocate(); }", completionHandler: nil)
        return true
    }
}
