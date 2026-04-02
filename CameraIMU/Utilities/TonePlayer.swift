import AudioToolbox
import Foundation

/// Plays short feedback sounds using system sounds (no AVAudioEngine needed).
/// This avoids conflicts with AVCaptureSession on sideloaded apps.
class TonePlayer {
    static let shared = TonePlayer()

    private init() {}

    func configureAudioSession() {
        // No-op: system sounds don't need audio session configuration
    }

    /// Triple-beep for start (3 short beeps)
    func playStartTone() {
        // 1052 = standard system "tock" sound
        AudioServicesPlayAlertSound(1052)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AudioServicesPlayAlertSound(1052)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            AudioServicesPlayAlertSound(1052)
        }
    }

    /// Single long beep for stop
    func playStopTone() {
        // 1521 = haptic vibration + sound (Peek)
        AudioServicesPlayAlertSound(1521)
    }
}
