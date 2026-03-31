import Foundation

struct Recording: Identifiable {
    let id = UUID()
    let date: Date
    let videoURL: URL
    let csvURL: URL

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    var videoFileSize: String {
        fileSize(for: videoURL)
    }

    var csvFileSize: String {
        fileSize(for: csvURL)
    }

    private func fileSize(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "N/A"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
