#!/bin/bash

# Agente de detección de software para macOS
# Este script detecta aplicaciones instaladas y envía la información a una API

# Función para obtener información del sistema una sola vez
get_system_info() {
    # Obtener nombre de usuario
    username=$(whoami)
    
    # Obtener dirección MAC (primera interfaz activa)
    mac_address=$(ifconfig | grep ether | head -n 1 | awk '{print $2}')
    
    # Si no se encuentra, intentar con otro método
    if [ -z "$mac_address" ]; then
        mac_address=$(networksetup -listallhardwareports | grep -A 3 "Wi-Fi" | grep "Ethernet Address" | awk '{print $3}')
    fi
    
    # Si aún no se encuentra, usar un valor por defecto
    if [ -z "$mac_address" ]; then
        mac_address="00:00:00:00:00:00"
    fi
    
    if [ "$DEBUG" = true ]; then
        echo "Información del sistema:"
        echo "  Usuario: $username"
        echo "  Dirección MAC: $mac_address"
    fi
    
    # Devolver como array
    echo "$username|$mac_address"
}

# Función para calcular el hash SHA256 de un archivo
calculate_sha256() {
    local file_path="$1"
    local sha256=""
    
    if [ -f "$file_path" ]; then
        sha256=$(shasum -a 256 "$file_path" 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -z "$sha256" ]; then
        sha256="no_disponible"
    fi
    
    echo "$sha256"
}

# Función para encontrar el ejecutable principal de una aplicación
find_main_executable() {
    local app_path="$1"
    local executable=""
    
    # Intentar encontrar el ejecutable en la estructura típica
    if [ -d "$app_path/Contents/MacOS" ]; then
        # Buscar el primer archivo ejecutable
        for file in "$app_path/Contents/MacOS"/*; do
            if [ -x "$file" ] && [ -f "$file" ]; then
                executable="$file"
                break
            fi
        done
    fi
    
    # Si no se encuentra, intentar con el nombre de la app
    if [ -z "$executable" ]; then
        local app_name=$(basename "$app_path" .app)
        potential_exe="$app_path/Contents/MacOS/$app_name"
        if [ -x "$potential_exe" ] && [ -f "$potential_exe" ]; then
            executable="$potential_exe"
        fi
    fi
    
    echo "$executable"
}

# Función para encontrar aplicaciones instaladas en el sistema
get_installed_apps() {
    local apps=()
    system_info=$(get_system_info)
    username=$(echo "$system_info" | cut -d'|' -f1)
    mac_address=$(echo "$system_info" | cut -d'|' -f2)
    
    if [ "$DEBUG" = true ]; then
        echo "Escaneando aplicaciones instaladas en /Applications..."
    fi
    
    # Solo buscar en /Applications como solicitado
    applications_dir="/Applications"
    
    # Comprobar si el directorio /Applications existe
    if [ -d "$applications_dir" ]; then
        # Buscar todas las aplicaciones en /Applications directamente
        for app in "$applications_dir"/*.app; do
            if [ -d "$app" ] && [[ "$app" != "*/*" ]]; then
                # Extraer solo el nombre de la aplicación sin la ruta ni la extensión
                app_name=$(basename "$app" .app)
                
                # Intentar obtener la versión
                version="desconocida"
                if [ -f "$app/Contents/Info.plist" ]; then
                    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null)
                    if [ $? -ne 0 ] || [ -z "$version" ]; then
                        version="desconocida"
                    fi
                fi
                
                # Encontrar ejecutable principal y calcular SHA256
                main_executable=$(find_main_executable "$app")
                sha256="no_disponible"
                
                if [ ! -z "$main_executable" ]; then
                    sha256=$(calculate_sha256 "$main_executable")
                fi
                
                # Añadir la aplicación al array en formato JSON
                apps+=("{\"nombre\":\"$app_name\",\"version\":\"$version\",\"ruta\":\"$app\",\"sha256\":\"$sha256\",\"username\":\"$username\",\"mac_address\":\"$mac_address\"}")
                
                # Mostrar progreso si está en modo debug
                if [ "$DEBUG" = true ]; then
                    echo "  Encontrada: $app_name (versión: $version)"
                fi
            fi
        done
        
        # Buscar en subdirectorios (solo un nivel)
        for subdir in "$applications_dir"/*/; do
            if [ -d "$subdir" ] && [[ "$subdir" != *"/.Trash/"* ]] && [[ "$subdir" != *"/Caches/"* ]]; then
                if [ "$DEBUG" = true ]; then
                    echo "  Escaneando subdirectorio: $(basename "$subdir")"
                fi
                
                for app in "$subdir"/*.app; do
                    if [ -d "$app" ] && [[ "$app" != "*/*" ]]; then
                        # Extraer solo el nombre de la aplicación
                        app_name=$(basename "$app" .app)
                        
                        # Intentar obtener la versión
                        version="desconocida"
                        if [ -f "$app/Contents/Info.plist" ]; then
                            version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null)
                            if [ $? -ne 0 ] || [ -z "$version" ]; then
                                version="desconocida"
                            fi
                        fi
                        
                        # Encontrar ejecutable principal y calcular SHA256
                        main_executable=$(find_main_executable "$app")
                        sha256="no_disponible"
                        
                        if [ ! -z "$main_executable" ]; then
                            sha256=$(calculate_sha256 "$main_executable")
                        fi
                        
                        # Añadir la aplicación al array en formato JSON
                        apps+=("{\"nombre\":\"$app_name\",\"version\":\"$version\",\"ruta\":\"$app\",\"sha256\":\"$sha256\",\"username\":\"$username\",\"mac_address\":\"$mac_address\"}")
                        
                        # Mostrar progreso si está en modo debug
                        if [ "$DEBUG" = true ]; then
                            echo "    Encontrada: $app_name (versión: $version)"
                        fi
                    fi
                done
            fi
        done
    else
        if [ "$DEBUG" = true ]; then
            echo "El directorio /Applications no existe"
        fi
    fi
    
    # Crear el objeto JSON final con las aplicaciones únicas
    # Eliminar duplicados sería más complejo con JSON, pero mostrar una lista única
    unique_apps=($(printf "%s\n" "${apps[@]}" | sort -u))
    
    if [ "$DEBUG" = true ]; then
        echo "Total de aplicaciones encontradas en /Applications: ${#unique_apps[@]}"
    fi
    
    # Devolver el array JSON
    echo "[$(IFS=,; echo "${unique_apps[*]}")]"
}

# Función para enviar datos a la API
send_apps_to_api() {
    local apps_json="$1"
    local api_url="http://127.0.0.1:5000"
    
    if [ "$DEBUG" = true ]; then
        echo "Enviando datos a $api_url..."
        echo "Datos a enviar: $(echo "$apps_json" | head -c 100)... (truncado)"
    fi
    
    # Enviar datos mediante curl (silenciosamente a menos que esté en modo debug)
    if [ "$DEBUG" = true ]; then
        response=$(curl -s -X POST -H "Content-Type: application/json" -d "$apps_json" "$api_url" 2>&1)
        curl_status=$?
        echo "Respuesta de la API: $response (status: $curl_status)"
    else
        curl -s -X POST -H "Content-Type: application/json" -d "$apps_json" "$api_url" >/dev/null 2>&1
    fi
}

# Función para ejecutar en modo daemon
run_as_daemon() {
    if [ "$DEBUG" = true ]; then
        echo "Iniciando en modo daemon..."
    fi
    
    # Lógica para ejecutarse como servicio
    # TODO: Implementar la instalación como servicio del sistema
    
    if [ "$DEBUG" = true ]; then
        echo "Modo daemon pendiente de implementación"
    fi
    
    exit 0
}

# Punto de entrada principal
main() {
    # Comprobar si se ha pasado la opción para depuración
    if [ "$1" = "--debug" ]; then
        DEBUG=true
        echo "Modo de depuración activado"
    else
        DEBUG=false
    fi
    
    # Comprobar si se ha pasado la opción para ejecutar como daemon
    if [ "$1" = "--daemon" ] || [ "$2" = "--daemon" ]; then
        run_as_daemon
    fi
    
    # Bucle principal - ejecutar cada 10 segundos
    while true; do
        # Obtener la lista de aplicaciones instaladas
        apps_json=$(get_installed_apps)
        
        # Enviar aplicaciones a la API
        send_apps_to_api "$apps_json"
        
        # Esperar antes de volver a escanear
        sleep 10
    done
}

# Ejecutar la función principal con los argumentos proporcionados
main "$@" 