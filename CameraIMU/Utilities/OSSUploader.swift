import CommonCrypto
import Foundation

/// Uploads files to Aliyun OSS using the REST API.
class OSSUploader {
    static let shared = OSSUploader()

    private let endpoint = "oss-cn-shanghai.aliyuncs.com"
    private let bucket = "xrobot-model-shanghai"
    private let prefix = "cu6/egocentric/test/"

    private let accessKey: String
    private let secretKey: String
    private let session: URLSession

    private init() {
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

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }

    /// Upload a file to OSS. Returns the OSS key on success.
    func upload(
        fileURL: URL,
        subfolder: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        let fileName = fileURL.lastPathComponent
        let ossKey = prefix + subfolder + "/" + fileName

        let fileData = try Data(contentsOf: fileURL)
        let contentType = contentType(for: fileURL.pathExtension)

        let url = URL(string: "https://\(bucket).\(endpoint)/\(ossKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

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

        let (_, response) = try await session.upload(for: request, from: fileData)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OSSError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OSSError.httpError(httpResponse.statusCode)
        }

        return ossKey
    }

    /// Upload multiple files for a recording session.
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

        onProgress("Uploading video...")
        let videoKey = try await upload(fileURL: videoURL, subfolder: subfolder)
        onProgress("Video uploaded")

        onProgress("Uploading IMU data...")
        let csvKey = try await upload(fileURL: csvURL, subfolder: subfolder)
        onProgress("Upload complete")

        print("OSSUploader: uploaded \(videoKey) and \(csvKey)")
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

enum OSSError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "Upload failed (HTTP \(code))"
        }
    }
}
