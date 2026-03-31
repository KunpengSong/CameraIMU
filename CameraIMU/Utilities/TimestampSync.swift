import CoreMedia
import Foundation

struct SyncAnchor {
    let hostTimeSeconds: Double
    let systemUptime: Double
    let wallClock: Date

    static func capture() -> SyncAnchor {
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        let hostSeconds = CMTimeGetSeconds(hostTime)
        let uptime = ProcessInfo.processInfo.systemUptime
        let wall = Date()
        return SyncAnchor(
            hostTimeSeconds: hostSeconds,
            systemUptime: uptime,
            wallClock: wall
        )
    }

    var csvHeader: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        # sync_host_time_seconds=\(String(format: "%.6f", hostTimeSeconds))
        # sync_system_uptime_seconds=\(String(format: "%.6f", systemUptime))
        # sync_wall_clock=\(formatter.string(from: wallClock))
        """
    }
}
