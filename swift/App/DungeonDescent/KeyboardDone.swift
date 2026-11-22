import SwiftUI
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit

/// 12.0.2: a "Hide Keyboard" button above the keyboard in every text box.
/// Several boxes (multi-line ones, search fields with no Return action) had no
/// way to close the keyboard, and with VoiceOver it stayed over the screen
/// until the app was restarted.
@MainActor
enum KeyboardDone {
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { attach(to: n.object as? UITextField) }
        })
        observers.append(center.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { attach(to: n.object as? UITextView) }
        })
    }

    private static func attach(to field: UITextField?) {
        guard let field, field.inputAccessoryView == nil else { return }
        field.inputAccessoryView = bar()
        field.reloadInputViews()
    }

    private static func attach(to view: UITextView?) {
        guard let view, view.inputAccessoryView == nil else { return }
        view.inputAccessoryView = bar()
        view.reloadInputViews()
    }

    private static func bar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let done = UIBarButtonItem(title: Language.t("Hide Keyboard"), primaryAction: UIAction { _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
        done.accessibilityLabel = Language.t("Hide keyboard")
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        bar.sizeToFit()
        return bar
    }
}
#else
@MainActor
enum KeyboardDone {
    static func install() {}
}
#endif
