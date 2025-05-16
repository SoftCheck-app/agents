import Cocoa
import Foundation

@main
class InstallMonitorApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: InstallMonitor?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: "Install Monitor")
        }
        
        // Create the menu
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Estado: Activo", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Ver Registro", action: #selector(showLog), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Preferencias", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        // Initialize and start the monitor
        monitor = InstallMonitor()
        monitor?.startMonitoring()
    }
    
    @objc func showLog() {
        // TODO: Implement log viewer
    }
    
    @objc func showPreferences() {
        // TODO: Implement preferences window
    }
}

// MARK: - Install Monitor Class
class InstallMonitor {
    private let backendURL = "http://34.175.247.105:4002/api"
    private let verificationEndpoint: String
    private let apiKey = "d8bae5d252a00496a84ab9c73c766ff4"
    private let appsDirectory = "/Applications"
    private let quarantineDirectory: String
    private var fileMonitor: FileMonitor?
    
    init() {
        verificationEndpoint = "\(backendURL)/validate_software"
        quarantineDirectory = "\(NSHomeDirectory())/Library/Application Support/AppQuarantine"
        setupQuarantineDirectory()
    }
    
    private func setupQuarantineDirectory() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: quarantineDirectory) {
            try? fileManager.createDirectory(atPath: quarantineDirectory,
                                          withIntermediateDirectories: true,
                                          attributes: [FileAttributeKey.posixPermissions: 0o700])
        }
    }
    
    func startMonitoring() {
        fileMonitor = FileMonitor(path: appsDirectory)
        fileMonitor?.delegate = self
        fileMonitor?.startMonitoring()
    }
}

// MARK: - File Monitor Delegate
extension InstallMonitor: FileMonitorDelegate {
    func fileMonitor(_ monitor: FileMonitor, didDetectNewFile path: String) {
        // Process new application
        processNewApplication(at: path)
    }
}

// MARK: - File Monitor Class
protocol FileMonitorDelegate: AnyObject {
    func fileMonitor(_ monitor: FileMonitor, didDetectNewFile path: String)
}

class FileMonitor {
    private let path: String
    private var source: DispatchSourceFileSystemObject?
    private var directoryHandle: FileHandle?
    weak var delegate: FileMonitorDelegate?
    
    init(path: String) {
        self.path = path
    }
    
    func startMonitoring() {
        guard let directoryHandle = FileHandle(forReadingAtPath: path) else { return }
        self.directoryHandle = directoryHandle
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryHandle.fileDescriptor,
            eventMask: .write,
            queue: .main
        )
        
        source.setEventHandler { [weak self] in
            self?.checkForNewFiles()
        }
        
        source.setCancelHandler { [weak self] in
            self?.directoryHandle?.closeFile()
        }
        
        self.source = source
        source.resume()
    }
    
    private func checkForNewFiles() {
        // Implementation for checking new files
        // This will be called when changes are detected in the directory
    }
} 