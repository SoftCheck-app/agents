#!/bin/bash
#
# MacOSInstallAgent - Monitor de instalaciones para macOS
# Este agente monitorea continuamente los cambios en el directorio de aplicaciones,
# verifica nuevas instalaciones con un servidor central, y bloquea aplicaciones no autorizadas.
#
# Características:
# - Detección de nuevas aplicaciones en /Applications
# - Verificación de software con un servidor central
# - Cuarentena de aplicaciones no autorizadas
# - No requiere contraseñas administrativas
# - Funciona silenciosamente en segundo plano

# Variables de configuración
BACKEND_URL="http://34.175.247.105:4002/api"
VERIFICATION_ENDPOINT="$BACKEND_URL/validate_software"
API_KEY="d8bae5d252a00496a84ab9c73c766ff4"  # Debe coincidir con el valor en la base de datos
APPS_DIRECTORY="/Applications"
SCAN_INTERVAL=10  # segundos entre escaneos
QUARANTINE_DIR="$HOME/Library/Application Support/AppQuarantine"

# Asegurar que la carpeta de cuarentena exista con permisos adecuados
setup_quarantine() {
  mkdir -p "$QUARANTINE_DIR"
  chmod 700 "$QUARANTINE_DIR"
  echo "Carpeta de cuarentena configurada: $QUARANTINE_DIR"
}

# Obtener nombre de usuario actual
get_username() {
  echo $(whoami)
}

# Obtener ID único del dispositivo
get_device_id() {
  local serial=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | awk '{print $4}')
  if [ -z "$serial" ]; then
    # Si no podemos obtener el número de serie, usamos la dirección MAC
    local mac=$(ifconfig | grep ether | head -n 1 | awk '{print $2}')
    echo "MAC-${mac//:/}"
  else
    echo "SERIAL-$serial"
  fi
}

# Calcular hash SHA256 de un archivo
calculate_sha256() {
  local file_path="$1"
  if [ -f "$file_path" ]; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    echo "no_disponible"
  fi
}

# Encontrar el ejecutable principal de una aplicación
find_main_executable() {
  local app_path="$1"
  local macos_path="${app_path}/Contents/MacOS"
  
  if [ -d "$macos_path" ]; then
    # Obtener el primer ejecutable en el directorio MacOS
    local exe_file=$(ls -1 "$macos_path" | head -n 1)
    if [ -n "$exe_file" ]; then
      echo "${macos_path}/${exe_file}"
      return 0
    fi
    
    # Intentar con el nombre de la app
    local app_name=$(basename "$app_path" .app)
    if [ -x "${macos_path}/${app_name}" ]; then
      echo "${macos_path}/${app_name}"
      return 0
    fi
  fi
  
  echo ""
  return 1
}

# Obtener la versión de una aplicación
get_app_version() {
  local app_path="$1"
  local plist_path="${app_path}/Contents/Info.plist"
  
  if [ -f "$plist_path" ]; then
    local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist_path" 2>/dev/null)
    if [ -n "$version" ]; then
      echo "$version"
      return 0
    fi
  fi
  
  echo "desconocida"
  return 1
}

# Obtener la empresa desarrolladora de una aplicación
get_app_vendor() {
  local app_path="$1"
  local plist_path="${app_path}/Contents/Info.plist"
  
  if [ -f "$plist_path" ]; then
    local vendor=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_path" 2>/dev/null | cut -d. -f2)
    if [ -n "$vendor" ]; then
      echo "$vendor"
      return 0
    fi
  fi
  
  echo "desconocido"
  return 1
}

# Verificar si una aplicación está siendo ejecutada
is_app_running() {
  local app_name="$1"
  ps aux | grep -v grep | grep -q "/Applications/${app_name}.app"
  if [ $? -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Verificar firma digital de la aplicación
check_digital_signature() {
  local app_path="$1"
  codesign -v "$app_path" 2>/dev/null
  if [ $? -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Obtener fecha de instalación aproximada (fecha de creación del directorio)
get_install_date() {
  local app_path="$1"
  local date_str=$(stat -f "%SB" -t "%Y-%m-%dT%H:%M:%SZ" "$app_path" 2>/dev/null)
  if [ -n "$date_str" ]; then
    echo "$date_str"
  else
    echo "null"
  fi
}

# Verificar si el software está autorizado con el servidor
verify_software() {
  local app_name="$1"
  local app_version="$2"
  local app_path="$3"
  local sha256="$4"
  local username="$5"
  local device_id="$6"
  local vendor="$7"
  local install_date="$8"
  local is_running="$9"
  local digital_signature="${10}"
  
  # Crear objeto JSON para verificación
  local json="{
    \"device_id\": \"$device_id\",
    \"user_id\": \"$username\",
    \"software_name\": \"$app_name\",
    \"version\": \"$app_version\",
    \"vendor\": \"$vendor\",
    \"install_date\": \"$install_date\",
    \"install_path\": \"$app_path\",
    \"install_method\": \"manual\",
    \"last_executed\": null,
    \"is_running\": $is_running,
    \"digital_signature\": $digital_signature,
    \"is_approved\": false,
    \"detected_by\": \"macos_agent\",
    \"sha256\": \"$sha256\",
    \"notes\": null
  }"
  
  # Enviar solicitud de verificación y obtener código de respuesta HTTP
  local response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -d "$json" \
    "$VERIFICATION_ENDPOINT")
  
  local success=$(echo "$response" | grep -o '"success":true' | wc -l)
  
  echo "Verificación para $app_name: respuesta $response"
  
  # Retornar true (0) si está autorizado (respuesta con success:true)
  if [ "$success" -gt 0 ]; then
    return 0
  else
    return 1
  fi
}

# Mover aplicación a cuarentena usando métodos nativos
move_to_quarantine() {
  local app_path="$1"
  local app_name=$(basename "$app_path")
  local quarantine_path="$QUARANTINE_DIR/$app_name"
  
  # Crear un script temporal de AppleScript para mover usando Finder
  local tmp_script=$(mktemp)
  cat > "$tmp_script" << EOF
tell application "Finder"
  set sourceItem to POSIX file "$app_path" as alias
  set targetFolder to POSIX file "$QUARANTINE_DIR" as alias
  
  if exists POSIX file "$quarantine_path" then
    delete POSIX file "$quarantine_path"
  end if
  
  move sourceItem to targetFolder with replacing
end tell
EOF
  
  # Ejecutar el script AppleScript
  osascript "$tmp_script" > /dev/null 2>&1
  local result=$?
  rm "$tmp_script"
  
  if [ $result -eq 0 ]; then
    echo "Aplicación movida a cuarentena: $quarantine_path"
    echo "$quarantine_path"
    return 0
  else
    # Intentar método alternativo con mv
    mv -f "$app_path" "$QUARANTINE_DIR/" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "Aplicación movida a cuarentena (método alternativo): $quarantine_path"
      echo "$quarantine_path"
      return 0
    else
      echo "Error al mover a cuarentena: $app_path"
      echo ""
      return 1
    fi
  fi
}

# Restaurar aplicación desde cuarentena
restore_from_quarantine() {
  local quarantine_path="$1"
  local app_name=$(basename "$quarantine_path")
  local destination_path="$APPS_DIRECTORY/$app_name"
  
  # Crear un script temporal de AppleScript para mover usando Finder
  local tmp_script=$(mktemp)
  cat > "$tmp_script" << EOF
tell application "Finder"
  set sourceItem to POSIX file "$quarantine_path" as alias
  set targetFolder to POSIX file "$APPS_DIRECTORY" as alias
  
  if exists POSIX file "$destination_path" then
    delete POSIX file "$destination_path"
  end if
  
  move sourceItem to targetFolder with replacing
end tell
EOF
  
  # Ejecutar el script AppleScript
  osascript "$tmp_script" > /dev/null 2>&1
  local result=$?
  rm "$tmp_script"
  
  if [ $result -eq 0 ]; then
    echo "Aplicación restaurada desde cuarentena: $destination_path"
    return 0
  else
    # Intentar método alternativo con mv
    mv -f "$quarantine_path" "$APPS_DIRECTORY/" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "Aplicación restaurada (método alternativo): $destination_path"
      return 0
    else
      echo "Error al restaurar desde cuarentena: $quarantine_path"
      return 1
    fi
  fi
}

# Eliminar permanentemente una aplicación
delete_application() {
  local app_path="$1"
  
  # Crear un script temporal de AppleScript para eliminar usando Finder
  local tmp_script=$(mktemp)
  cat > "$tmp_script" << EOF
tell application "Finder"
  delete POSIX file "$app_path"
end tell
EOF
  
  # Ejecutar el script AppleScript
  osascript "$tmp_script" > /dev/null 2>&1
  local result=$?
  rm "$tmp_script"
  
  if [ $result -eq 0 ]; then
    echo "Aplicación eliminada: $app_path"
    return 0
  else
    # Intentar método alternativo con rm
    rm -rf "$app_path" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "Aplicación eliminada (método alternativo): $app_path"
      return 0
    else
      # Tercer método: mover a la papelera con AppleScript
      local trash_script=$(mktemp)
      cat > "$trash_script" << EOF
tell application "Finder"
  set itemToDelete to POSIX file "$app_path" as alias
  delete itemToDelete
end tell
EOF
      osascript "$trash_script" > /dev/null 2>&1
      result=$?
      rm "$trash_script"
      
      if [ $result -eq 0 ]; then
        echo "Aplicación movida a la papelera: $app_path"
        return 0
      else
        echo "Error al eliminar aplicación: $app_path"
        return 1
      fi
    fi
  fi
}

# Mostrar notificación en macOS
show_notification() {
  local title="$1"
  local message="$2"
  
  osascript -e "display notification \"$message\" with title \"$title\""
}

# Mostrar diálogo al usuario
show_dialog() {
  local title="$1"
  local message="$2"
  local icon="$3"  # note, caution, stop
  
  osascript -e "display dialog \"$message\" buttons {\"OK\"} default button 1 with title \"$title\" with icon $icon"
}

# Procesar una nueva aplicación detectada
process_new_application() {
  local app_name="$1"
  local app_path="$2"
  
  # Recopilar información
  local app_version=$(get_app_version "$app_path")
  local username=$(get_username)
  local device_id=$(get_device_id)
  local main_executable=$(find_main_executable "$app_path")
  local vendor=$(get_app_vendor "$app_path")
  local install_date=$(get_install_date "$app_path")
  local is_running=$(is_app_running "$app_name")
  local digital_signature=$(check_digital_signature "$app_path")
  local sha256="no_disponible"
  
  if [ -n "$main_executable" ]; then
    sha256=$(calculate_sha256 "$main_executable")
  fi
  
  # Mostrar diálogo de información
  local dialog_text="Se ha detectado la instalación de una nueva aplicación: $app_name\n\nVersión: $app_version\nDesarrollador: $vendor\nRuta: $app_path\nSHA256: $sha256\nUsuario: $username\n\nLa instalación ha sido bloqueada temporalmente mientras se verifica con el servidor."
  show_dialog "Instalación Detectada" "$dialog_text" "caution"
  
  # Mover a cuarentena temporalmente
  local quarantine_path=$(move_to_quarantine "$app_path")
  
  if [ -n "$quarantine_path" ]; then
    # Verificar si el software está autorizado
    if verify_software "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature"; then
      # Software autorizado, restaurar desde cuarentena
      if restore_from_quarantine "$quarantine_path"; then
        show_dialog "Software Autorizado" "El software $app_name está autorizado. La instalación ha sido permitida." "note"
      else
        show_dialog "Error de Restauración" "El software $app_name está autorizado, pero hubo un problema al restaurarlo. Por favor, contacte al administrador." "stop"
      fi
    else
      # Software no autorizado, eliminar permanentemente
      if delete_application "$quarantine_path"; then
        show_dialog "Software No Autorizado" "El software $app_name NO está autorizado en la base de datos. La instalación ha sido bloqueada." "stop"
      else
        show_dialog "Error de Eliminación" "El software $app_name NO está autorizado, pero hubo un problema al eliminarlo. Por favor, contacte al administrador." "stop"
      fi
    fi
  else
    show_dialog "Error de Bloqueo" "No se pudo bloquear la instalación de $app_name. Por favor, contacte al administrador." "stop"
  fi
}

# Obtener lista actual de aplicaciones instaladas
get_current_apps() {
  find "$APPS_DIRECTORY" -maxdepth 1 -name "*.app" -print0 | xargs -0 -n1 basename
}

# Verificar si una aplicación existe en la lista
app_exists() {
  local app_name="$1"
  local app_list="$2"
  
  echo "$app_list" | grep -q "^$app_name$"
  return $?
}

# Función principal que ejecuta el ciclo de monitoreo
run_monitor() {
  echo "Iniciando monitor de instalaciones..."
  
  # Configurar carpeta de cuarentena
  setup_quarantine
  
  # Obtener lista inicial de aplicaciones
  local initial_apps=$(get_current_apps)
  
  # Guardar lista inicial para debug (opcional)
  echo "$initial_apps" > "/tmp/initial_apps.txt"
  echo "Se han detectado $(echo "$initial_apps" | wc -l | tr -d ' ') aplicaciones iniciales que NO generarán alertas."
  
  # Mostrar notificación de inicio
  show_notification "Monitor de Instalaciones" "Monitor de instalaciones iniciado"
  
  # Bucle principal
  while true; do
    # Obtener lista actual de aplicaciones
    local current_apps=$(get_current_apps)
    
    # Buscar nuevas aplicaciones
    while IFS= read -r app; do
      if [ -n "$app" ] && ! app_exists "$app" "$initial_apps"; then
        echo "Nueva aplicación detectada: $app"
        
        # Extraer nombre sin extensión .app
        local app_name="${app%.app}"
        
        # Procesar la nueva aplicación
        process_new_application "$app_name" "$APPS_DIRECTORY/$app"
        
        # Actualizar lista de aplicaciones conocidas
        initial_apps=$(echo -e "$initial_apps\n$app")
      fi
    done < <(echo "$current_apps")
    
    # Esperar antes del siguiente escaneo
    sleep $SCAN_INTERVAL
  done
}

# --- Iniciar el agente ---
run_monitor 