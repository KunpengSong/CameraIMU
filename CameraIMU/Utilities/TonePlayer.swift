import AVFoundation
import Foundation

/// Plays start/stop audio feedback using bundled MP3 files.
class TonePlayer {
    static let shared = TonePlayer()

    private var audioPlayer: AVAudioPlayer?

    private init() {}

    func configureAudioSession() {
        // no-op kept for API compatibility
    }

    func playStartTone() {
        play(resource: "start", ext: "mp3")
    }

    func playStopTone() {
        play(resource: "end", ext: "mp3")
    }

    private func play(resource: String, ext: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("TonePlayer: \(resource).\(ext) not found in bundle")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {
            print("TonePlayer error: \(error)")
        }
    }
}
