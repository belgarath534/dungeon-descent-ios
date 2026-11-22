import CoreMotion
import Foundation

/// Shake to Attack (initShakeToAttack): during a fight, a shake attacks and a
/// hard shake uses your first skill you can afford. Same thresholds as the
/// web version (15 and 25 m/s², about 1.5 g and 2.5 g), 0.8 s apart.
/// The accelerometer needs no permission on iOS.
@MainActor
final class ShakeDetector {
    static let shared = ShakeDetector()

    private let motion = CMMotionManager()
    private var last = Date.distantPast
    /// Called with true for a hard shake.
    var onShake: ((Bool) -> Void)?

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, AppSettings.shakeAttack, let a = data?.userAcceleration else { return }
            let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard g > 1.53, Date().timeIntervalSince(self.last) > 0.8 else { return }
            self.last = Date()
            self.onShake?(g > 2.55)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
