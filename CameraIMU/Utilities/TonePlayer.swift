import AVFoundation
import Foundation

/// Plays short ascending (start) or descending (stop) tones using AVAudioEngine.
class TonePlayer {
    static let shared = TonePlayer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private let duration: Double = 0.3  // total tone duration in seconds

    private init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    /// Ascending two-note tone: C5 → E5
    func playStartTone() {
        playTwoNoteTone(freq1: 523.0, freq2: 659.0)
    }

    /// Descending two-note tone: E5 → C5
    func playStopTone() {
        playTwoNoteTone(freq1: 659.0, freq2: 523.0)
    }

    private func playTwoNoteTone(freq1: Double, freq2: Double) {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)!

        let totalFrames = Int(sampleRate * duration)
        let halfFrames = totalFrames / 2

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: AVAudioFrameCount(totalFrames)) else { return }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        let data = buffer.floatChannelData![0]

        // First note
        for i in 0..<halfFrames {
            let envelope = fadeEnvelope(sample: i, total: halfFrames)
            let sample = Float(0.5 * envelope * sin(2.0 * .pi * freq1 * Double(i) / sampleRate))
            data[i] = sample
        }
        // Second note
        for i in 0..<halfFrames {
            let envelope = fadeEnvelope(sample: i, total: halfFrames)
            let sample = Float(0.5 * envelope * sin(2.0 * .pi * freq2 * Double(i) / sampleRate))
            data[halfFrames + i] = sample
        }

        do {
            // Configure audio session to mix with recording
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)

            if !engine.isRunning {
                try engine.start()
            }
            playerNode.stop()
            playerNode.scheduleBuffer(buffer, at: nil)
            playerNode.play()
        } catch {
            print("TonePlayer error: \(error)")
        }
    }

    /// Fade-in/fade-out envelope to avoid clicks. ~10% fade on each end.
    private func fadeEnvelope(sample: Int, total: Int) -> Double {
        let fadeSamples = total / 10
        if sample < fadeSamples {
            return Double(sample) / Double(fadeSamples)
        } else if sample > total - fadeSamples {
            return Double(total - sample) / Double(fadeSamples)
        }
        return 1.0
    }
}
