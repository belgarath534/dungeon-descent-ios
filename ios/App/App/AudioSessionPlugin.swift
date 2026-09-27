import Foundation
import Capacitor
import AVFoundation

// Capacitor's default WebView audio session behavior isn't tuned for a
// game that leans entirely on sound for information a sighted player
// would get visually. The specific problem this addresses: VoiceOver's
// own speech appears to duck (attenuate) other app audio while it talks,
// and the app's audio session category/options influence how aggressively
// that happens — though Apple doesn't fully document the exact interaction
// with VoiceOver specifically, so `.playback` + `.mixWithOthers` is our
// best documented lever, not a guaranteed fix. It needs confirming on a
// real device with VoiceOver running, the same way the room3D exit-cue
// timing fix did.
@objc(AudioSessionPlugin)
public class AudioSessionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AudioSessionPlugin"
    public let jsName = "AudioSession"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "configureForGameplay", returnType: CAPPluginReturnPromise)
    ]

    @objc func configureForGameplay(_ call: CAPPluginCall) {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback: keeps audio playing even if the ringer/silent
            // switch is on — this game needs sound to function at all,
            // it's not optional background music.
            // .mixWithOthers: lets the game's audio coexist with other
            // active audio sources instead of claiming exclusive control,
            // which is the option most likely to affect how VoiceOver's
            // speech and this app's sound interact.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            call.resolve()
        } catch {
            call.reject("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}
