import Foundation
import AppKit

class AppQuarantine {
    private let quarantineDirectory: String
    private let fileManager = FileManager.default
    
    init(quarantineDirectory: String) {
        self.quarantineDirectory = quarantineDirectory
        setupQuarantineDirectory()
    }
    
    private func setupQuarantineDirectory() {
        if !fileManager.fileExists(atPath: quarantineDirectory) {
            try? fileManager.createDirectory(atPath: quarantineDirectory,
                                          withIntermediateDirectories: true,
                                          attributes: [FileAttributeKey.posixPermissions: 0o700])
        }
    }
    
    func quarantineApplication(at path: String) async throws -> String {
        let appName = URL(fileURLWithPath: path).lastPathComponent
        let quarantinePath = (quarantineDirectory as NSString).appendingPathComponent(appName)
        
        // Remove existing quarantine if any
        if fileManager.fileExists(atPath: quarantinePath) {
            try fileManager.removeItem(atPath: quarantinePath)
        }
        
        // Move to quarantine
        try fileManager.moveItem(atPath: path, toPath: quarantinePath)
        
        return quarantinePath
    }
    
    func restoreApplication(from quarantinePath: String) async throws -> String {
        let appName = URL(fileURLWithPath: quarantinePath).lastPathComponent
        let destinationPath = "/Applications/\(appName)"
        
        // Remove existing app if any
        if fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(atPath: destinationPath)
        }
        
        // Move back to Applications
        try fileManager.moveItem(atPath: quarantinePath, toPath: destinationPath)
        
        return destinationPath
    }
    
    func deleteApplication(at path: String) async throws {
        try fileManager.removeItem(atPath: path)
    }
    
    func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func showAlert(title: String, message: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
} 