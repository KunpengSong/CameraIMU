import Foundation

struct IMUSample {
    let timestamp: Double
    // Acceleration (gravity + user acceleration) in G
    let accelX: Double
    let accelY: Double
    let accelZ: Double
    // Rotation rate in rad/s
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double
    // Magnetic field in microteslas
    let magX: Double
    let magY: Double
    let magZ: Double

    static let csvColumnHeader = "timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z"

    var csvRow: String {
        String(format: "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f",
               timestamp, accelX, accelY, accelZ,
               gyroX, gyroY, gyroZ,
               magX, magY, magZ)
    }
}
