import AudioToolbox
import Foundation

/// Plays short feedback sounds using system sounds (no AVAudioEngine needed).
/// This avoids conflicts with AVCaptureSession on sideloaded apps.
class TonePlayer {
    static let shared = TonePlayer()

    private var startSoundID: SystemSoundID = 0
    private var stopSoundID: SystemSoundID = 0

    private init() {
        // System sounds: 1057 = ascending tink, 1053 = descending tink
        // These are built-in iOS system sound IDs
        startSoundID = 1057
        stopSoundID = 1053
    }

    func configureAudioSession() {
        // No-op: system sounds don't need audio session configuration
    }

    /// Ascending feedback sound for start
    func playStartTone() {
        AudioServicesPlaySystemSound(startSoundID)
    }

    /// Descending feedback sound for stop
    func playStopTone() {
        AudioServicesPlaySystemSound(stopSoundID)
    }
}
