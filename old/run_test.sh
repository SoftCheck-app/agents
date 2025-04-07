#!/bin/bash

# Script para ejecutar el agente en modo de prueba (sin instalación)

echo "Ejecutando el agente en modo de prueba..."
echo "Esto mostrará las aplicaciones en /Applications pero NO las enviará a la API."
echo "Las aplicaciones se enviarían en formato JSON como un único mensaje cada 10 segundos."
echo ""

# Crear un array para almacenar las aplicaciones en formato JSON
apps=()

# Obtener información del sistema una sola vez
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
    
    echo "Información del sistema:"
    echo "  Usuario: $username"
    echo "  Dirección MAC: $mac_address"
    echo ""
    
    # Devolver como array
    echo "$username|$mac_address"
}

# Obtener la información del sistema
system_info=$(get_system_info)
username=$(echo "$system_info" | cut -d'|' -f1)
mac_address=$(echo "$system_info" | cut -d'|' -f2)

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

# Solo buscar en /Applications como solicitado
applications_dir="/Applications"

# Función para procesar una aplicación encontrada
process_app() {
    local app_path="$1"
    
    # Extraer solo el nombre de la aplicación sin la ruta ni la extensión
    local app_name=$(basename "$app_path" .app)
    local version=""
    
    # Intentar obtener la versión si está disponible
    if [ -f "$app_path/Contents/Info.plist" ]; then
        version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist" 2>/dev/null)
        
        if [ $? -ne 0 ] || [ -z "$version" ]; then
            version="desconocida"
        fi
    else
        version="desconocida"
    fi
    
    # Encontrar ejecutable principal y calcular SHA256
    local main_executable=$(find_main_executable "$app_path")
    local sha256="no_disponible"
    
    if [ ! -z "$main_executable" ]; then
        sha256=$(calculate_sha256 "$main_executable")
    fi
    
    # Para mostrar en la salida de prueba (versión resumida)
    echo "  - $app_name (versión: $version)"
    echo "    Ruta: $app_path"
    echo "    SHA256: ${sha256:0:16}... (truncado)"
    
    # Añadir la aplicación al array en formato JSON completo
    apps+=("{\"nombre\":\"$app_name\",\"version\":\"$version\",\"ruta\":\"$app_path\",\"sha256\":\"$sha256\",\"username\":\"$username\",\"mac_address\":\"$mac_address\"}")
}

# Explorar cada directorio
echo "Escaneando aplicaciones instaladas en /Applications:"
echo "=================================================="

# Comprobar si el directorio /Applications existe
if [ -d "$applications_dir" ]; then
    # Buscar todas las aplicaciones en /Applications directamente
    for app in "$applications_dir"/*.app; do
        if [ -d "$app" ] && [[ "$app" != "*/*" ]]; then
            process_app "$app"
        fi
    done
    
    # Buscar en subdirectorios (solo un nivel para evitar buscar demasiado profundo)
    for subdir in "$applications_dir"/*/; do
        if [ -d "$subdir" ] && [[ "$subdir" != *"/.Trash/"* ]] && [[ "$subdir" != *"/Caches/"* ]]; then
            echo ""
            echo "En subdirectorio $(basename "$subdir"):"
            for app in "$subdir"/*.app; do
                if [ -d "$app" ] && [[ "$app" != "*/*" ]]; then
                    process_app "$app"
                fi
            done
        fi
    done
else
    echo "El directorio /Applications no existe"
fi

# Eliminar duplicados (más complejo con JSON, pero intentamos hacerlo)
unique_apps=($(printf "%s\n" "${apps[@]}" | sort -u))

# Crear el objeto JSON final
json_data="[$(IFS=,; echo "${unique_apps[*]}")]"

echo "=================================="
echo "Total de aplicaciones únicas encontradas en /Applications: ${#unique_apps[@]}"

# Buscar específicamente Notion y Obsidian para confirmar
echo ""
echo "Buscando aplicaciones específicas (formato JSON):"

# Búsqueda en el JSON usando grep y mostrar con formato legible
for app_name in "Notion" "Obsidian"; do
    app_json=$(echo "$json_data" | grep -o "{\"nombre\":\"$app_name\"[^}]*}" | head -n 1)
    if [ ! -z "$app_json" ]; then
        echo "$app_name encontrado:"
        # Formatear JSON para mejor legibilidad
        echo "$app_json" | sed 's/,/,\n    /g' | sed 's/{/{\n    /' | sed 's/}/\n}/'
    else
        echo "$app_name: No encontrado"
    fi
    echo ""
done

echo "Ejemplo de formato JSON que se enviaría a la API (muestra de una aplicación):"
# Tomar el primer elemento del array y formatearlo para que sea legible
echo "$json_data" | grep -o "{\([^}]*\)}" | head -n 1 | sed 's/,/,\n    /g' | sed 's/{/{\n    /' | sed 's/}/\n}/'

echo ""
echo "En modo real, estas aplicaciones serían enviadas a: http://127.0.0.1:5000"
echo "como un único objeto JSON cada 10 segundos mediante una petición POST."
echo ""
echo "Para ejecutar el agente real que envía los datos, use:"
echo "./AppScanner.sh"
echo ""
echo "Para configurar el agente para que se ejecute automáticamente, use:"
echo "./AppScanner.sh --daemon" 