import Foundation
import Security

class AppVerification {
    private let backendURL: String
    private let apiKey: String
    
    init(backendURL: String, apiKey: String) {
        self.backendURL = backendURL
        self.apiKey = apiKey
    }
    
    func verifyApplication(at path: String) async throws -> Bool {
        let appInfo = try await gatherAppInfo(path: path)
        return try await sendVerificationRequest(appInfo: appInfo)
    }
    
    private func gatherAppInfo(path: String) async throws -> [String: Any] {
        let fileManager = FileManager.default
        let appURL = URL(fileURLWithPath: path)
        
        // Get app bundle info
        guard let bundle = Bundle(url: appURL) else {
            throw NSError(domain: "AppVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid application bundle"])
        }
        
        // Get main executable
        guard let executablePath = bundle.executablePath else {
            throw NSError(domain: "AppVerification", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not find executable"])
        }
        
        // Calculate SHA256
        let sha256 = try await calculateSHA256(filePath: executablePath)
        
        // Get device info
        let deviceID = getDeviceID()
        let username = NSUserName()
        
        return [
            "device_id": deviceID,
            "user_id": username,
            "software_name": bundle.bundleIdentifier ?? "unknown",
            "version": bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "vendor": bundle.infoDictionary?["CFBundleIdentifier"] as? String ?? "unknown",
            "install_date": try fileManager.attributesOfItem(atPath: path)[.creationDate] as? Date ?? Date(),
            "install_path": path,
            "install_method": "manual",
            "is_running": isAppRunning(bundleIdentifier: bundle.bundleIdentifier ?? ""),
            "digital_signature": verifyCodeSignature(path: path),
            "sha256": sha256
        ]
    }
    
    private func calculateSHA256(filePath: String) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        let bufferSize = 1024 * 1024 // 1MB buffer
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        
        while let data = try fileHandle.read(upToCount: bufferSize), !data.isEmpty {
            data.withUnsafeBytes { buffer in
                CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(data.count))
            }
        }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func getDeviceID() -> String {
        if let serial = getSerialNumber() {
            return "SERIAL-\(serial)"
        }
        return "MAC-\(getMACAddress())"
    }
    
    private func getSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        
        guard platformExpert != 0 else { return nil }
        
        return IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? String
    }
    
    private func getMACAddress() -> String {
        // Implementation to get MAC address
        return "unknown"
    }
    
    private func isAppRunning(bundleIdentifier: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    private func verifyCodeSignature(path: String) -> Bool {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else { return false }
        
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }
    
    private func sendVerificationRequest(appInfo: [String: Any]) async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/validate_software") else {
            throw NSError(domain: "AppVerification", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        
        let jsonData = try JSONSerialization.data(withJSONObject: appInfo)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        return response?["success"] as? Bool ?? false
    }
} 