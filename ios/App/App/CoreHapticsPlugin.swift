import Foundation
import Capacitor
import CoreHaptics

// Capacitor's stock Haptics plugin only exposes fixed-length "impact" taps —
// every pattern in the game, from a 100ms tap to a 500ms death buzz, felt
// like the exact same brief click (see the fallback comment in vibe() in
// index.html, which layers a plain vibrate() under the tap to fake a
// duration). Core Haptics (iOS 13+) exposes CHHapticEngine directly, so a
// pattern's actual duration, intensity, and sharpness can be felt for real.
@objc(CoreHapticsPlugin)
public class CoreHapticsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CoreHapticsPlugin"
    public let jsName = "CoreHaptics"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isSupported", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "playPattern", returnType: CAPPluginReturnPromise)
    ]

    private var engine: CHHapticEngine?

    // The engine stops itself when the app backgrounds or on some system
    // interruptions, so it's re-created lazily on the next play rather than
    // kept alive eagerly — a stopped engine is the normal state most of the
    // time this plugin isn't actively firing a pattern.
    private func ensureEngine() -> CHHapticEngine? {
        if let engine = engine { return engine }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        do {
            let newEngine = try CHHapticEngine()
            newEngine.stoppedHandler = { [weak self] _ in self?.engine = nil }
            newEngine.resetHandler = { [weak self] in
                guard let self = self else { return }
                try? self.engine?.start()
            }
            try newEngine.start()
            engine = newEngine
            return newEngine
        } catch {
            return nil
        }
    }

    @objc func isSupported(_ call: CAPPluginCall) {
        call.resolve(["supported": CHHapticEngine.capabilitiesForHardware().supportsHaptics])
    }

    @objc func playPattern(_ call: CAPPluginCall) {
        guard let engine = ensureEngine() else {
            call.reject("Core Haptics not supported on this device")
            return
        }
        guard let rawEvents = call.getArray("events") as? [[String: Any]], !rawEvents.isEmpty else {
            call.reject("Missing events array")
            return
        }
        var hapticEvents: [CHHapticEvent] = []
        for raw in rawEvents {
            let time = raw["time"] as? Double ?? 0
            let duration = raw["duration"] as? Double ?? 0
            let intensity = Float(raw["intensity"] as? Double ?? 1.0)
            let sharpness = Float(raw["sharpness"] as? Double ?? 0.5)
            let isContinuous = (raw["type"] as? String) == "continuous"
            let params = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ]
            let event = CHHapticEvent(
                eventType: isContinuous ? .hapticContinuous : .hapticTransient,
                parameters: params,
                relativeTime: time,
                duration: isContinuous ? max(duration, 0.01) : 0
            )
            hapticEvents.append(event)
        }
        do {
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            call.resolve()
        } catch {
            call.reject("Failed to play haptic pattern: \(error.localizedDescription)")
        }
    }
}
