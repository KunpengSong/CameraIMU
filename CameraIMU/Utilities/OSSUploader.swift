import CommonCrypto
import Foundation

/// Uploads files to Aliyun OSS using the REST API with progress tracking.
class OSSUploader: NSObject {
    static let shared = OSSUploader()

    private let endpoint = "oss-cn-shanghai.aliyuncs.com"
    private let bucket = "xrobot-model-shanghai"
    private let prefix = "cu6/egocentric/test/"

    private let accessKey: String
    private let secretKey: String
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Progress tracking
    private var activeProgress: ((Int64, Int64) -> Void)?
    private var activeCompletion: ((Result<Int, Error>) -> Void)?
    private var responseData = Data()
    private var uploadStartTime: Date = Date()

    private override init() {
        // Load credentials from OSSConfig.plist (not tracked in git)
        if let url = Bundle.main.url(forResource: "OSSConfig", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
            accessKey = dict["AccessKey"] ?? ""
            secretKey = dict["SecretKey"] ?? ""
        } else {
            accessKey = ""
            secretKey = ""
            print("OSSUploader: OSSConfig.plist not found — uploads will fail")
        }
        super.init()
    }

    /// Upload a single file to OSS with progress callback.
    /// progressHandler receives (bytesSent, totalBytes).
    func upload(
        fileURL: URL,
        subfolder: String,
        progressHandler: @escaping (Int64, Int64) -> Void
    ) async throws -> String {
        let fileName = fileURL.lastPathComponent
        let ossKey = prefix + subfolder + "/" + fileName
        let contentType = contentType(for: fileURL.pathExtension)

        // Get file size
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        let url = URL(string: "https://\(bucket).\(endpoint)/\(ossKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

        let dateString = rfc822Date()
        request.setValue(dateString, forHTTPHeaderField: "Date")

        let signature = sign(
            verb: "PUT",
            contentMD5: "",
            contentType: contentType,
            date: dateString,
            resource: "/\(bucket)/\(ossKey)"
        )
        request.setValue("OSS \(accessKey):\(signature)", forHTTPHeaderField: "Authorization")

        // Use delegate-based upload for progress tracking
        let statusCode: Int = try await withCheckedThrowingContinuation { continuation in
            self.activeProgress = progressHandler
            self.activeCompletion = { result in continuation.resume(with: result) }
            self.responseData = Data()
            self.uploadStartTime = Date()
            // Upload from file — streams from disk, doesn't load entire file into memory
            let task = self.session.uploadTask(with: request, fromFile: fileURL)
            task.resume()
        }

        guard (200..<300).contains(statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            print("OSS error response: \(body)")
            throw OSSError.httpError(statusCode, body)
        }

        return ossKey
    }

    /// Upload video + CSV for a recording session.
    func uploadRecording(
        videoURL: URL,
        csvURL: URL,
        deviceName: String,
        onProgress: @escaping (String) -> Void
    ) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let subfolder = "\(deviceName)/\(dateStr)"

        // Upload video with progress
        _ = try await upload(fileURL: videoURL, subfolder: subfolder) { sent, total in
            let pct = total > 0 ? Int(Double(sent) / Double(total) * 100) : 0
            let elapsed = Date().timeIntervalSince(self.uploadStartTime)
            let speed = elapsed > 0 ? Double(sent) / elapsed : 0
            let speedStr = self.formatSpeed(speed)
            onProgress("Video: \(pct)% (\(speedStr))")
        }
        onProgress("Video uploaded. Uploading IMU...")

        // Upload CSV (small, usually instant)
        _ = try await upload(fileURL: csvURL, subfolder: subfolder) { sent, total in
            let pct = total > 0 ? Int(Double(sent) / Double(total) * 100) : 0
            onProgress("IMU: \(pct)%")
        }
        onProgress("Upload complete")
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec > 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec > 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    // MARK: - OSS Signature

    private func sign(verb: String, contentMD5: String, contentType: String, date: String, resource: String) -> String {
        let stringToSign = "\(verb)\n\(contentMD5)\n\(contentType)\n\(date)\n\(resource)"
        return hmacSHA1(key: secretKey, data: stringToSign)
    }

    private func hmacSHA1(key: String, data: String) -> String {
        let keyBytes = Array(key.utf8)
        let dataBytes = Array(data.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), keyBytes, keyBytes.count, dataBytes, dataBytes.count, &digest)
        return Data(digest).base64EncodedString()
    }

    private func rfc822Date() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }

    private func contentType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "csv": return "text/csv"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - URLSession Delegate for progress

extension OSSUploader: URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        activeProgress?(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            activeCompletion?(.failure(error))
        } else {
            let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            activeCompletion?(.success(statusCode))
        }
        activeProgress = nil
        activeCompletion = nil
    }
}

enum OSSError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code, let body):
            // Extract OSS error message if available
            if let range = body.range(of: "<Message>"),
               let endRange = body.range(of: "</Message>") {
                let msg = body[range.upperBound..<endRange.lowerBound]
                return "HTTP \(code): \(msg)"
            }
            return "Upload failed (HTTP \(code))"
        }
    }
}
