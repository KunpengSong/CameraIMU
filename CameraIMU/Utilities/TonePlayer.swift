import AVFoundation
import Foundation

/// Plays short tones using AVAudioPlayer with in-memory WAV data.
/// Avoids AVAudioEngine (which crashes with AVCaptureSession on sideloaded apps).
class TonePlayer {
    static let shared = TonePlayer()

    private var audioPlayer: AVAudioPlayer?
    private let sampleRate: Double = 44100
    private let duration: Double = 0.3

    private init() {}

    func configureAudioSession() {
        // no-op kept for API compatibility
    }

    /// Ascending two-note tone: C5 → E5
    func playStartTone() {
        playTone(freq1: 523.0, freq2: 659.0)
    }

    /// Descending two-note tone: E5 → C5
    func playStopTone() {
        playTone(freq1: 659.0, freq2: 523.0)
    }

    private func playTone(freq1: Double, freq2: Double) {
        let totalSamples = Int(sampleRate * duration)
        let halfSamples = totalSamples / 2

        // Generate 16-bit PCM samples
        var samples = [Int16](repeating: 0, count: totalSamples)

        for i in 0..<halfSamples {
            let envelope = fadeEnvelope(sample: i, total: halfSamples)
            let value = 0.8 * envelope * sin(2.0 * .pi * freq1 * Double(i) / sampleRate)
            samples[i] = Int16(value * Double(Int16.max))
        }
        for i in 0..<halfSamples {
            let envelope = fadeEnvelope(sample: i, total: halfSamples)
            let value = 0.8 * envelope * sin(2.0 * .pi * freq2 * Double(i) / sampleRate)
            samples[halfSamples + i] = Int16(value * Double(Int16.max))
        }

        // Build WAV file in memory
        let wavData = buildWAV(samples: samples, sampleRate: Int(sampleRate))

        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {
            print("TonePlayer error: \(error)")
        }
    }

    private func fadeEnvelope(sample: Int, total: Int) -> Double {
        let fadeSamples = total / 10
        if sample < fadeSamples {
            return Double(sample) / Double(fadeSamples)
        } else if sample > total - fadeSamples {
            return Double(total - sample) / Double(fadeSamples)
        }
        return 1.0
    }

    private func buildWAV(samples: [Int16], sampleRate: Int) -> Data {
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(numChannels * (bitsPerSample / 8))
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let chunkSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: chunkSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: Int32(16))        // chunk size
        data.append(littleEndian: Int16(1))          // PCM format
        data.append(littleEndian: numChannels)
        data.append(littleEndian: Int32(sampleRate))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)

        for sample in samples {
            data.append(littleEndian: sample)
        }

        return data
    }
}

private extension Data {
    mutating func append(littleEndian value: Int16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
    mutating func append(littleEndian value: Int32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
