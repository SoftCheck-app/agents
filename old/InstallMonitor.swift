import Foundation
import AppKit
import Cocoa

// Sistema de interceptación de instalación de software para macOS
// Muestra un popup cuando detecta la instalación de una aplicación y envía la información a un backend

// Clase para monitorear directorios de instalación
class InstallationMonitor {
    // Directorios a monitorear (principalmente /Applications)
    private let monitoredDirectories = ["/Applications"]
    private var fileWatchers: [DispatchSourceFileSystemObject] = []
    private var knownApplications: Set<String> = []
    private var apiUrl = "http://127.0.0.1:5000"
    
    // Inicialización del monitor
    init() {
        // Cargar las aplicaciones conocidas en el momento de inicio
        loadInitialApplications()
        
        // Configurar el monitoreo de directorios
        setupFileWatchers()
    }
    
    // Carga las aplicaciones iniciales para evitar falsos positivos
    private func loadInitialApplications() {
        for directory in monitoredDirectories {
            let fileManager = FileManager.default
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: directory)
                // Filtrar por archivos .app
                let apps = contents.filter { $0.hasSuffix(".app") }
                for app in apps {
                    let fullPath = "\(directory)/\(app)"
                    knownApplications.insert(fullPath)
                    print("App inicial: \(fullPath)")
                }
            } catch {
                print("Error al leer directorio \(directory): \(error)")
            }
        }
    }
    
    // Configura los observadores de cambios en los directorios
    private func setupFileWatchers() {
        for directory in monitoredDirectories {
            let fileManager = FileManager.default
            
            // Verificar que el directorio existe
            guard fileManager.fileExists(atPath: directory) else {
                print("El directorio \(directory) no existe")
                continue
            }
            
            // Obtener el descriptor de archivo
            guard let fd = open(directory, O_EVTONLY) else {
                print("No se pudo abrir el descriptor de \(directory)")
                continue
            }
            
            let directoryFD = Int32(fd)
            
            // Crear el observador
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: directoryFD,
                eventMask: .write,
                queue: DispatchQueue.global(qos: .default)
            )
            
            // Definir el manejador de eventos
            source.setEventHandler { [weak self] in
                self?.checkForNewApplications(in: directory)
            }
            
            // Manejador para cerrar el descriptor cuando se cancela
            source.setCancelHandler {
                close(directoryFD)
            }
            
            // Activar el observador
            source.resume()
            fileWatchers.append(source)
            
            print("Monitoreo establecido para \(directory)")
        }
    }
    
    // Verifica nuevas aplicaciones en el directorio
    private func checkForNewApplications(in directory: String) {
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: directory)
            // Filtrar por archivos .app
            let apps = contents.filter { $0.hasSuffix(".app") }
            
            for app in apps {
                let fullPath = "\(directory)/\(app)"
                
                // Verificar si es una aplicación nueva
                if !knownApplications.contains(fullPath) {
                    // Detectada nueva aplicación
                    print("¡Nueva aplicación detectada! \(fullPath)")
                    
                    // Procesar la nueva aplicación
                    processNewApplication(at: fullPath)
                    
                    // Agregar a la lista de conocidas
                    knownApplications.insert(fullPath)
                }
            }
        } catch {
            print("Error al leer directorio \(directory): \(error)")
        }
    }
    
    // Procesa una nueva aplicación detectada
    private func processNewApplication(at path: String) {
        // Extraer información de la aplicación
        let appName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        var version = "desconocida"
        var sha256 = "no_disponible"
        let username = NSUserName()
        let macAddress = getMacAddress()
        
        // Obtener la versión si está disponible
        if let bundle = Bundle(path: path),
           let bundleVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            version = bundleVersion
        }
        
        // Encontrar el ejecutable principal
        let mainExecutable = findMainExecutable(at: path)
        
        // Calcular SHA256 si encontramos el ejecutable
        if !mainExecutable.isEmpty {
            sha256 = calculateSHA256(of: mainExecutable)
        }
        
        // Crear el objeto JSON
        let appInfo: [String: String] = [
            "nombre": appName,
            "version": version,
            "ruta": path,
            "sha256": sha256,
            "username": username,
            "mac_address": macAddress
        ]
        
        // Mostrar el popup de aprobación
        DispatchQueue.main.async {
            self.showApprovalPopup(for: appInfo)
        }
    }
    
    // Muestra un popup para aprobar la instalación
    private func showApprovalPopup(for appInfo: [String: String]) {
        // Convertir a JSON para mostrar y enviar
        guard let jsonData = try? JSONSerialization.data(withJSONObject: appInfo, options: .prettyPrinted),
              let prettyJson = String(data: jsonData, encoding: .utf8) else {
            print("Error al crear el JSON")
            return
        }
        
        // Crear el alert en el hilo principal
        let alert = NSAlert()
        alert.messageText = "Instalación de aplicación detectada"
        alert.informativeText = "Se ha detectado la instalación de \(appInfo["nombre"] ?? "una aplicación").\n\nDetalles:\n\(prettyJson)"
        alert.alertStyle = .warning
        
        // Botones de acción
        alert.addButton(withTitle: "Permitir y enviar datos")
        alert.addButton(withTitle: "Denegar instalación")
        
        // Mostrar el alert y procesar respuesta
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Permitir y enviar datos
            print("Usuario aprobó la instalación y el envío de datos")
            sendApplicationDataToAPI(appInfo: appInfo)
        } else {
            // Denegar la instalación (intento de eliminar la aplicación)
            print("Usuario denegó la instalación, intentando eliminar la aplicación")
            deleteApplication(path: appInfo["ruta"] ?? "")
        }
    }
    
    // Envía los datos al backend
    private func sendApplicationDataToAPI(appInfo: [String: String]) {
        // Convertir a JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [appInfo], options: []) else {
            print("Error al convertir los datos a JSON")
            return
        }
        
        // Crear la solicitud
        guard let url = URL(string: apiUrl) else {
            print("URL inválida: \(apiUrl)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Enviar la solicitud
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error al enviar datos a la API: \(error)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Respuesta de la API: \(httpResponse.statusCode)")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Respuesta: \(responseString)")
                }
            }
        }
        task.resume()
    }
    
    // Intenta eliminar la aplicación si el usuario deniega la instalación
    private func deleteApplication(path: String) {
        let fileManager = FileManager.default
        
        do {
            try fileManager.removeItem(atPath: path)
            print("Aplicación eliminada exitosamente: \(path)")
        } catch {
            print("Error al eliminar la aplicación: \(error)")
            
            // Mostrar mensaje de error
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Error al desinstalar la aplicación"
                alert.informativeText = "No se pudo eliminar la aplicación. Es posible que necesite permisos de administrador.\n\nError: \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    // Encuentra el ejecutable principal de una aplicación
    private func findMainExecutable(at appPath: String) -> String {
        var executable = ""
        
        // Intentar encontrar el ejecutable en la estructura típica
        let macosPath = "\(appPath)/Contents/MacOS"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: macosPath) {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: macosPath)
                for file in contents {
                    let fullPath = "\(macosPath)/\(file)"
                    var isDir: ObjCBool = false
                    
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) && !isDir.boolValue {
                        let attributes = try fileManager.attributesOfItem(atPath: fullPath)
                        if let permissions = attributes[.posixPermissions] as? NSNumber {
                            // Verificar si es ejecutable (permiso x)
                            if (permissions.intValue & 0o111) != 0 {
                                executable = fullPath
                                break
                            }
                        }
                    }
                }
            } catch {
                print("Error al buscar el ejecutable: \(error)")
            }
        }
        
        // Si no se encuentra, intentar con el nombre de la app
        if executable.isEmpty {
            let appName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let potentialPath = "\(macosPath)/\(appName)"
            
            if fileManager.fileExists(atPath: potentialPath) {
                executable = potentialPath
            }
        }
        
        return executable
    }
    
    // Calcula el hash SHA256 de un archivo - versión simplificada
    private func calculateSHA256(of filePath: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        task.arguments = ["-a", "256", filePath]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let components = output.components(separatedBy: " ")
                if !components.isEmpty {
                    return components[0].trimmingCharacters(in: .whitespaces)
                }
            }
        } catch {
            print("Error al calcular SHA256: \(error)")
        }
        
        return "no_disponible"
    }
    
    // Obtiene la dirección MAC del sistema - versión simplificada
    private func getMacAddress() -> String {
        // Valor predeterminado en caso de error
        let defaultMAC = "00:00:00:00:00:00"
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Búsqueda simplificada para MAC
                for line in output.components(separatedBy: .newlines) {
                    if line.contains("ether") {
                        let components = line.components(separatedBy: " ")
                        for component in components {
                            // Comprobar formato de MAC común xx:xx:xx:xx:xx:xx
                            if component.count == 17 && component.contains(":") {
                                return component
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error al obtener dirección MAC: \(error)")
        }
        
        return defaultMAC
    }
}

// Ventana principal que actúa como controlador para la aplicación
class AppController: NSObject, NSApplicationDelegate {
    var monitor: InstallationMonitor?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Monitor de instalaciones iniciado")
        
        // Iniciar el monitor
        monitor = InstallationMonitor()
    }
}

// Punto de entrada principal
// No usamos @main para evitar problemas de compilación con versiones antiguas de Swift
class InstallMonitorApp {
    static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        
        // Crear un menú simple
        let mainMenu = NSMenu(title: "Monitor de Instalaciones")
        mainMenu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.mainMenu = mainMenu
        
        // Configurar un ícono en la barra de menú
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.cautionName)
            button.action = #selector(NSApplication.terminate(_:))
            button.target = app
        }
        
        print("Iniciando aplicación de monitoreo de instalaciones...")
        app.run()
    }
}

// Función main() para iniciar la aplicación
func main() {
    InstallMonitorApp.main()
}

// Llamar a la función main para iniciar la aplicación
main() 