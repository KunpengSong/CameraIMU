import CoreMotion
import Foundation

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "imu-sampling"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let lock = NSLock()
    private var samples: [IMUSample] = []
    private(set) var syncAnchor: SyncAnchor?

    @Published var isRecording = false
    @Published var sampleCount: Int = 0

    var isDeviceMotionAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    func startRecording() -> SyncAnchor {
        let anchor = SyncAnchor.capture()
        syncAnchor = anchor

        lock.lock()
        samples.removeAll()
        samples.reserveCapacity(18_000) // ~10 min at 30Hz
        lock.unlock()

        DispatchQueue.main.async {
            self.sampleCount = 0
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: queue
        ) { [weak self] motion, error in
            guard let self, let motion else { return }

            let sample = IMUSample(
                timestamp: motion.timestamp,
                accelX: motion.gravity.x + motion.userAcceleration.x,
                accelY: motion.gravity.y + motion.userAcceleration.y,
                accelZ: motion.gravity.z + motion.userAcceleration.z,
                gyroX: motion.rotationRate.x,
                gyroY: motion.rotationRate.y,
                gyroZ: motion.rotationRate.z,
                magX: motion.magneticField.field.x,
                magY: motion.magneticField.field.y,
                magZ: motion.magneticField.field.z
            )

            self.lock.lock()
            self.samples.append(sample)
            let count = self.samples.count
            self.lock.unlock()

            // Update UI every 30 samples (~1s) to avoid flooding the main thread
            if count % 30 == 0 {
                DispatchQueue.main.async {
                    self.sampleCount = count
                }
            }
        }

        DispatchQueue.main.async {
            self.isRecording = true
        }
        return anchor
    }

    func stopRecording() -> [IMUSample] {
        motionManager.stopDeviceMotionUpdates()

        lock.lock()
        let collected = samples
        samples.removeAll()
        lock.unlock()

        DispatchQueue.main.async {
            self.isRecording = false
            self.sampleCount = collected.count
        }
        return collected
    }
}
