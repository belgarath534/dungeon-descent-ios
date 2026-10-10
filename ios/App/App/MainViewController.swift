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
    // Plugins that live in the app itself (not npm packages) aren't found by
    // Capacitor automatically, so without this they'd never reach the game:
    // iCloud backup, audio session, haptics and the Live Activity would all
    // silently do nothing.
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(AudioSessionPlugin())
        bridge?.registerPluginInstance(CoreHapticsPlugin())
        bridge?.registerPluginInstance(LiveActivityPlugin())
        bridge?.registerPluginInstance(iCloudSyncPlugin())
    }

    override func accessibilityPerformMagicTap() -> Bool {
        webView?.evaluateJavaScript("if (typeof echoLocate === 'function') { echoLocate(); }", completionHandler: nil)
        return true
    }
}
