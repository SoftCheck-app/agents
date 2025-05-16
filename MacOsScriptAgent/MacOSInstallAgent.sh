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
#BACKEND_URL="http://34.175.247.105:4002/api"
BACKEND_URL="http://localhost:4002/api"
VERIFICATION_ENDPOINT="$BACKEND_URL/validate_software"
API_KEY="305f98c40f6ab0224759d1725147ca1b"  # Debe coincidir con el valor en la base de datos
APPS_DIRECTORY="/Applications"
SCAN_INTERVAL=10  # segundos entre escaneos
QUARANTINE_DIR="$HOME/Library/Application Support/AppQuarantine"
SETTINGS_ENDPOINT="$BACKEND_URL/settings"  # Endpoint para obtener ajustes
STATUS_ENDPOINT="$BACKEND_URL/agents/status"
PING_ENDPOINT="$BACKEND_URL/agents/ping"  # Endpoint para enviar pings
SOFTWARE_STATUS_ENDPOINT="$BACKEND_URL/software/status"  # Endpoint para verificar estado de aprobación

# Configuración del agente
AGENT_STATUS="active"      # active/inactive - Determina si el agente está funcionando
AGENT_MODE="active"        # active/passive - En modo pasivo solo monitorea sin tomar acciones
AGENT_AUTO_UPDATE="true"   # true/false - Determina si el agente se actualiza automáticamente
AGENT_CONFIG_FILE="$HOME/.softcheck/agent_config.json"
PENDING_APPS_FILE="$HOME/.softcheck/pending_apps.json"

# Variable para controlar el nivel de verbosidad (0=silencioso, 1=normal, 2=detallado)
VERBOSE_LEVEL=2

# Variables para control de reintentos
RETRY_INTERVAL=300 # 5 minutos entre reintentos de verificación después de un fallo de auth
AUTH_FAILURE_TIME=0 # Tiempo del último fallo de autenticación
AUTH_FAILURE_REPORTED=0 # Para evitar mensajes repetitivos

# Función para imprimir mensajes de log según el nivel de verbosidad
log() {
  local level=$1
  local message=$2
  
  # Solo imprimir si el nivel de verbosidad actual es mayor o igual al nivel del mensaje
  if [ $VERBOSE_LEVEL -ge $level ]; then
    echo "$message"
  fi
}

# Función para imprimir las configuraciones actuales del agente (reducida)
print_agent_settings() {
  # Obtener el tiempo desde la última sincronización exitosa
  local now=$(date +%s)
  local sync_time_diff=$((now - LAST_SYNC_TIME))
  local sync_status="Nunca sincronizado"
  
  if [ $LAST_SYNC_TIME -gt 0 ]; then
    if [ $sync_time_diff -lt 120 ]; then
      sync_status="Sincronizado hace $sync_time_diff segundos"
    else
      sync_status="Sincronizado hace $((sync_time_diff / 60)) minutos"
    fi
  fi
  
  # Determinar el estado de la conexión al servidor
  local connection_status="DESCONECTADO"
  if [ $LAST_SYNC_TIME -gt 0 ] && [ $sync_time_diff -lt 300 ]; then
    connection_status="CONECTADO"
  fi
  
  log 1 "========================================"
  log 1 "  CONFIGURACIÓN ACTUAL DEL AGENTE"
  log 1 "========================================"
  log 1 " Status     : ${AGENT_STATUS} ($([ "$AGENT_STATUS" = "active" ] && echo "ACTIVO" || echo "INACTIVO"))"
  log 1 " Mode       : ${AGENT_MODE} ($([ "$AGENT_MODE" = "active" ] && echo "ACTIVO" || echo "PASIVO"))"
  log 1 " Device ID  : $(get_device_id)"
  log 1 " Servidor   : ${BACKEND_URL}"
  log 1 " Conexión   : ${connection_status}"
  log 1 "========================================"
}

# Asegurar que la carpeta de configuración exista
setup_config_dir() {
  mkdir -p "$HOME/.softcheck"
  chmod 700 "$HOME/.softcheck"
  log 2 "Carpeta de configuración configurada: $HOME/.softcheck"
}

# Verificar y cargar configuración guardada o crearla si no existe
load_or_create_config() {
  local device_id=$(get_device_id)
  local username=$(get_username)
  
  # Inicializar variable para la última sincronización exitosa
  LAST_SYNC_TIME=0
  
  if [ -f "$AGENT_CONFIG_FILE" ]; then
    # Verificar si el archivo de configuración es válido
    if jq -e . "$AGENT_CONFIG_FILE" >/dev/null 2>&1; then
      # Cargar configuración desde el archivo
      AGENT_STATUS=$(jq -r '.status // "active"' "$AGENT_CONFIG_FILE")
      AGENT_MODE=$(jq -r '.mode // "active"' "$AGENT_CONFIG_FILE")
      AGENT_AUTO_UPDATE=$(jq -r '.autoUpdate // true' "$AGENT_CONFIG_FILE")
      
      log 2 "Configuración cargada desde archivo local"
      print_agent_settings
    else
      log 1 "Archivo de configuración corrupto. Restaurando desde backup o creando uno nuevo."
      
      # Intentar restaurar desde backup
      if [ -f "${AGENT_CONFIG_FILE}.backup" ] && jq -e . "${AGENT_CONFIG_FILE}.backup" >/dev/null 2>&1; then
        cp "${AGENT_CONFIG_FILE}.backup" "$AGENT_CONFIG_FILE"
        AGENT_STATUS=$(jq -r '.status // "active"' "$AGENT_CONFIG_FILE")
        AGENT_MODE=$(jq -r '.mode // "active"' "$AGENT_CONFIG_FILE")
        AGENT_AUTO_UPDATE=$(jq -r '.autoUpdate // true' "$AGENT_CONFIG_FILE")
        log 2 "Configuración restaurada desde backup"
      else
        # Crear configuración por defecto
        AGENT_STATUS="active"
        AGENT_MODE="active"
        AGENT_AUTO_UPDATE=true
        update_config_file "$device_id" "$username"
        log 2 "Configuración por defecto creada"
      fi
      print_agent_settings
    fi
  else
    # Crear configuración inicial
    AGENT_STATUS="active"
    AGENT_MODE="active"
    AGENT_AUTO_UPDATE=true
    update_config_file "$device_id" "$username"
    log 2 "Configuración inicial creada"
    print_agent_settings
  fi
  
  # Sincronizar con el servidor para obtener la configuración actual
  sync_config_with_server
}

# Sincronizar configuración con el servidor
sync_config_with_server() {
  local device_id=$(get_device_id)
  local username=$(get_username)
  
  log 2 "Sincronizando configuración con el servidor..."
  log 2 "Device ID: $device_id"
  
  # Obtener configuración desde el servidor con cabeceras mejoradas
  local response=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    --connect-timeout 30 \
    "$SETTINGS_ENDPOINT")
  
  # Detectar errores HTTP comunes
  if [[ "$response" == *"DOCTYPE html"* ]] || [[ "$response" == *"login"* ]] || [[ "$response" == *"<html"* ]]; then
    log 1 "ERROR: Se recibió una página HTML en lugar de JSON. Posible problema de autenticación."
    return 1
  fi
  
  # Verificar si obtuvo respuesta válida JSON con isActive
  if [[ "$response" == *"\"isActive\""* ]]; then
    # Extraer valores del JSON (requiere jq instalado)
    if command -v jq &> /dev/null; then
      local isActive=$(echo "$response" | jq -r '.isActive')
      local isActiveMode=$(echo "$response" | jq -r '.isActiveMode')
      local autoUpdate=$(echo "$response" | jq -r '.autoUpdate')
      
      # Guardar configuración anterior para comparar cambios
      local previous_status="$AGENT_STATUS"
      local previous_mode="$AGENT_MODE"
      local previous_auto_update="$AGENT_AUTO_UPDATE"
      
      # Convertir true/false a active/inactive para status y mode
      if [ "$isActive" = "true" ]; then
        AGENT_STATUS="active"
      else
        AGENT_STATUS="inactive"
      fi
      
      if [ "$isActiveMode" = "true" ]; then
        AGENT_MODE="active"
      else
        AGENT_MODE="passive"
      fi
      
      AGENT_AUTO_UPDATE="$autoUpdate"
      
      # Verificar si hubo cambios en la configuración
      if [ "$previous_status" != "$AGENT_STATUS" ] || [ "$previous_mode" != "$AGENT_MODE" ] || [ "$previous_auto_update" != "$AGENT_AUTO_UPDATE" ]; then
        log 1 "Configuración actualizada: Status=$AGENT_STATUS, Mode=$AGENT_MODE"
      fi
      
      # Guardar configuración actualizada
      update_config_file "$device_id" "$username"
      
      # Establecer hora de última sincronización exitosa
      LAST_SYNC_TIME=$(date +%s)
      return 0
    else
      log 1 "Error: jq no está instalado"
      return 1
    fi
  else
    log 1 "No se pudo obtener la configuración del servidor"
    return 1
  fi
}

# Función para actualizar el archivo de configuración
update_config_file() {
  local device_id="$1"
  local username="$2"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Crear JSON con la configuración actual
  local config="{
    \"status\": \"$AGENT_STATUS\",
    \"mode\": \"$AGENT_MODE\",
    \"autoUpdate\": $AGENT_AUTO_UPDATE,
    \"deviceId\": \"$device_id\",
    \"username\": \"$username\",
    \"lastSync\": \"$timestamp\"
  }"
  
  # Guardar al archivo de configuración
  echo "$config" > "$AGENT_CONFIG_FILE"
  
  # También guardar a un archivo de respaldo
  echo "$config" > "${AGENT_CONFIG_FILE}.backup"
  
  log 2 "Archivo de configuración actualizado"
}

# Función para verificar actualizaciones del agente
check_for_updates() {
  log 2 "Verificando actualizaciones del agente..."
  
  if [ "$AGENT_AUTO_UPDATE" = "true" ]; then
    # Obtener la versión actual del script
    local current_version=$(grep "# Version:" "$0" | awk '{print $3}')
    
    # Verificar con el servidor si hay una nueva versión
    local update_response=$(curl -s -X GET \
      -H "X-API-KEY: $API_KEY" \
      "$BACKEND_URL/agents/updates?version=$current_version&deviceId=$(get_device_id)")
    
    # Comprobar si hay actualizaciones disponibles
    if [[ "$update_response" == *"updateAvailable"*"true"* ]]; then
      if command -v jq &> /dev/null; then
        local update_url=$(echo "$update_response" | jq -r '.updateUrl')
        
        # Descargar actualización
        log 1 "Actualizando el agente a la nueva versión..."
        curl -s -o "/tmp/agent_update.sh" "$update_url"
        
        if [ -f "/tmp/agent_update.sh" ]; then
          # Dar permisos de ejecución al nuevo script
          chmod +x "/tmp/agent_update.sh"
          
          # Crear un script que sustituya el actual con el nuevo
          cat > "/tmp/replace_agent.sh" << EOF
#!/bin/bash
# Esperar a que el proceso actual termine
sleep 2
# Reemplazar el script actual con la nueva versión
cp "/tmp/agent_update.sh" "$0"
# Limpiar archivos temporales
rm "/tmp/agent_update.sh"
rm "/tmp/replace_agent.sh"
# Reiniciar el agente
"$0" &
exit 0
EOF
          chmod +x "/tmp/replace_agent.sh"
          
          # Ejecutar el script de reemplazo en segundo plano y salir
          nohup "/tmp/replace_agent.sh" > /dev/null 2>&1 &
          log 1 "Agente actualizado. Reiniciando..."
          exit 0
        fi
      fi
    else
      log 2 "El agente está actualizado"
    fi
  fi
}

# Asegurar que la carpeta de cuarentena exista con permisos adecuados
setup_quarantine() {
  mkdir -p "$QUARANTINE_DIR"
  chmod 700 "$QUARANTINE_DIR"
  log 2 "Carpeta de cuarentena configurada: $QUARANTINE_DIR"
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
  
  log 1 "Verificando software: $app_name $app_version"
  
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
  
  # Enviar solicitud de verificación y obtener respuesta
  local temp_response_file=$(mktemp)
  local temp_headers_file=$(mktemp)
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    -d "$json" \
    "$VERIFICATION_ENDPOINT" \
    2> "$temp_headers_file" \
    > "$temp_response_file"
  
  local curl_exit_code=$?
  local response=$(cat "$temp_response_file")
  
  # Limpiar archivos temporales
  rm -f "$temp_response_file" "$temp_headers_file"
  
  # Verificar si curl tuvo error
  if [ $curl_exit_code -ne 0 ]; then
    log 1 "ERROR: curl falló con código $curl_exit_code"
    return 1
  fi
  
  # Extraer software_id y status de la respuesta si es posible (requiere jq)
  local software_id=""
  local status="pending"
  
  if command -v jq &> /dev/null; then
    if [[ "$response" == *"\"software\":"* ]]; then
      software_id=$(echo "$response" | jq -r '.software.id // ""')
      status=$(echo "$response" | jq -r '.software.status // "pending"')
      
      log 2 "Software ID: $software_id, Status: $status"
    elif [[ "$response" == *"\"softwareId\":"* ]]; then
      software_id=$(echo "$response" | jq -r '.softwareId // ""')
      is_approved=$(echo "$response" | jq -r '.isApproved // false')
      
      if [ "$is_approved" = "true" ]; then
        status="approved"
      else
        status="pending"
      fi
      
      log 2 "Software ID: $software_id, IsApproved: $is_approved, Mapped Status: $status"
    fi
  fi
  
  # Si no pudimos extraer status, verificar si hay success:true
  if [ -z "$status" ] || [ "$status" = "null" ]; then
    local success=$(echo "$response" | grep -o '"success":true' | wc -l)
    if [ "$success" -gt 0 ]; then
      status="approved"
    else
      status="pending"
    fi
  fi
  
  # Si tenemos un ID de software y el estado es "pending", guardar en lista de pendientes
  if [ -n "$software_id" ] && [ "$status" = "pending" ]; then
    add_to_pending_list "$app_name" "$app_version" "$app_path" "$software_id"
  fi
  
  log 1 "Resultado de verificación: $status"
  
  # Retornar resultado según el status
  if [ "$status" = "approved" ] || [ "$status" = "whitelist" ]; then
    return 0  # Aprobado
  elif [ "$status" = "blacklist" ]; then
    return 2  # Rechazado explícitamente
  else
    return 1  # Pendiente o desconocido
  fi
}

# Añadir una aplicación a la lista de pendientes
add_to_pending_list() {
  local app_name="$1"
  local app_version="$2"
  local app_path="$3"
  local software_id="$4"
  local timestamp=$(date +%s)
  
  # Crear directorio de configuración si no existe
  mkdir -p "$(dirname "$PENDING_APPS_FILE")"
  
  # Crear el archivo JSON si no existe
  if [ ! -f "$PENDING_APPS_FILE" ]; then
    echo "[]" > "$PENDING_APPS_FILE"
  fi
  
  # Leer el JSON actual
  local current_json=$(cat "$PENDING_APPS_FILE")
  
  # Añadir la nueva aplicación al JSON (requiere jq)
  if command -v jq &> /dev/null; then
    local new_entry="{
      \"software_id\": \"$software_id\",
      \"app_name\": \"$app_name\",
      \"app_version\": \"$app_version\",
      \"app_path\": \"$app_path\",
      \"timestamp\": $timestamp
    }"
    
    # Insertar el nuevo registro en el array
    local updated_json=$(echo "$current_json" | jq ". += [$new_entry]")
    echo "$updated_json" > "$PENDING_APPS_FILE"
    
    log 2 "Aplicación $app_name añadida a la lista de pendientes"
  else
    log 1 "No se pudo añadir a la lista de pendientes: jq no está instalado"
  fi
}

# Verificar estado de aplicaciones pendientes
check_pending_applications() {
  log 2 "Verificando aplicaciones pendientes..."
  
  # Verificar si hay aplicaciones pendientes
  if [ ! -f "$PENDING_APPS_FILE" ]; then
    log 2 "No hay aplicaciones pendientes"
    return 0
  fi
  
  # Leer la lista de aplicaciones pendientes
  local pending_apps=$(cat "$PENDING_APPS_FILE")
  
  # Si no hay jq instalado, no podemos procesar el JSON
  if ! command -v jq &> /dev/null; then
    log 1 "Error: jq no está instalado"
    return 1
  fi
  
  # Verificar si el JSON es válido
  if ! echo "$pending_apps" | jq empty 2>/dev/null; then
    log 1 "Archivo de aplicaciones pendientes corrupto. Creando nuevo archivo vacío"
    echo "[]" > "$PENDING_APPS_FILE"
    return 1
  fi
  
  # Contar cuántas aplicaciones hay pendientes
  local count=$(echo "$pending_apps" | jq '. | length')
  log 2 "$count aplicaciones pendientes encontradas"
  
  # Si no hay aplicaciones pendientes, salir
  if [ "$count" -eq 0 ]; then
    return 0
  fi
  
  # Verificar si ha pasado suficiente tiempo desde el último fallo de autenticación
  local now=$(date +%s)
  if [ $AUTH_FAILURE_TIME -gt 0 ] && [ $((now - AUTH_FAILURE_TIME)) -lt $RETRY_INTERVAL ]; then
    # Si no ha pasado suficiente tiempo desde el último fallo, saltar verificación
    local wait_time=$((RETRY_INTERVAL - (now - AUTH_FAILURE_TIME)))
    
    # Reportar sólo una vez por ciclo de espera
    if [ $AUTH_FAILURE_REPORTED -eq 0 ]; then
      log 1 "Esperando $wait_time segundos antes de reintentar verificaciones (problema de autenticación)"
      AUTH_FAILURE_REPORTED=1
    fi
    return 0
  fi
  
  # Resetear el flag de reporte
  AUTH_FAILURE_REPORTED=0
  
  # Array para almacenar IDs de aplicaciones a eliminar de la lista
  local apps_to_remove=()
  local auth_failed=0
  
  # Iterar sobre cada aplicación pendiente
  for i in $(seq 0 $(($count - 1))); do
    local software_id=$(echo "$pending_apps" | jq -r ".[$i].software_id")
    local app_name=$(echo "$pending_apps" | jq -r ".[$i].app_name")
    
    log 2 "Verificando estado de $app_name (ID: $software_id)..."
    
    # Verificar estado actual con el servidor
    local status_response=$(curl -s -X GET \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -H "Accept: application/json" \
      -H "User-Agent: SoftCheck-Agent/1.0" \
      "$SOFTWARE_STATUS_ENDPOINT/$software_id")
    
    # Verificar si la respuesta contiene una redirección a login
    if [[ "$status_response" == *"/auth/login"* ]] || [[ "$status_response" == *"DOCTYPE html"* ]] || [[ "$status_response" == *"<html"* ]]; then
      # Si es el primer fallo de autenticación en este ciclo
      if [ $auth_failed -eq 0 ]; then
        log 1 "ADVERTENCIA: Recibida redirección a página de login. Posible sesión expirada"
        
        # Intentar renovar la conexión con el servidor
        ping_server
        sync_config_with_server
        
        # Registrar tiempo de fallo para implementar backoff
        AUTH_FAILURE_TIME=$(date +%s)
        auth_failed=1
      fi
      
      # La aplicación continúa pendiente
      log 2 "$app_name sigue pendiente (problema de autenticación)"
      continue
    fi
    
    # Extraer el estado actual
    local current_status="pending"
    
    # Verificar si la respuesta es un JSON válido
    if echo "$status_response" | jq empty 2>/dev/null; then
      current_status=$(echo "$status_response" | jq -r '.status // "pending"')
      local rejection_reason=$(echo "$status_response" | jq -r '.reason // "No cumple con las políticas de seguridad"')
      log 2 "Estado actual: $current_status"
    else
      log 1 "ADVERTENCIA: Respuesta no válida del servidor"
      log 2 "$app_name sigue pendiente (respuesta del servidor no válida)"
      continue
    fi
    
    # Actuar según el estado
    if [ "$current_status" = "approved" ] || [ "$current_status" = "whitelist" ]; then
      log 1 "$app_name ha sido aprobado. Restaurando permisos de ejecución..."
      
      # Restaurar permisos de ejecución
      if restore_app_execution "$app_path"; then
        log 1 "Permisos restaurados para $app_name"
        apps_to_remove+=("$software_id")
      else
        show_dialog "Error de Restauración" "El software $app_name ha sido aprobado, pero hubo un problema al restaurar sus permisos." "stop"
      fi
    elif [ "$current_status" = "rejected" ] || [ "$current_status" = "blacklist" ] || [ "$current_status" = "denied" ]; then
      log 1 "$app_name ha sido rechazado. Eliminando..."
      
      # Mostrar el motivo del rechazo al usuario
      show_dialog "Software Rechazado" "El software $app_name ha sido rechazado.\n\nRazón: $rejection_reason" "stop"
      
      # Eliminar la aplicación
      if delete_application "$app_path"; then
        log 1 "Aplicación $app_name eliminada correctamente"
        apps_to_remove+=("$software_id")
      else
        show_dialog "Error de Eliminación" "El software $app_name ha sido rechazado, pero hubo un problema al eliminarlo." "stop"
      fi
    else
      log 2 "$app_name sigue pendiente"
    fi
  done
  
  # Eliminar aplicaciones procesadas de la lista de pendientes
  for id in "${apps_to_remove[@]}"; do
    log 2 "Eliminando $id de la lista de pendientes..."
    pending_apps=$(echo "$pending_apps" | jq "map(select(.software_id != \"$id\"))")
  done
  
  # Guardar la lista actualizada
  echo "$pending_apps" > "$PENDING_APPS_FILE"
  
  log 2 "Verificación de aplicaciones pendientes completada"
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
    log 2 "Aplicación movida a cuarentena: $quarantine_path"
    echo "$quarantine_path"
    return 0
  else
    # Intentar método alternativo con mv
    mv -f "$app_path" "$QUARANTINE_DIR/" 2>/dev/null
    if [ $? -eq 0 ]; then
      log 2 "Aplicación movida a cuarentena (método alternativo): $quarantine_path"
      echo "$quarantine_path"
      return 0
    else
      log 1 "Error al mover a cuarentena: $app_path"
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
    log 2 "Aplicación restaurada desde cuarentena: $destination_path"
    return 0
  else
    # Intentar método alternativo con mv
    mv -f "$quarantine_path" "$APPS_DIRECTORY/" 2>/dev/null
    if [ $? -eq 0 ]; then
      log 2 "Aplicación restaurada (método alternativo): $destination_path"
      return 0
    else
      log 1 "Error al restaurar desde cuarentena: $quarantine_path"
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
    log 2 "Aplicación eliminada: $app_path"
    return 0
  else
    # Intentar método alternativo con rm
    rm -rf "$app_path" 2>/dev/null
    if [ $? -eq 0 ]; then
      log 2 "Aplicación eliminada (método alternativo): $app_path"
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
        log 2 "Aplicación movida a la papelera: $app_path"
        return 0
      else
        log 1 "Error al eliminar aplicación: $app_path"
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

# Procesar una nueva aplicación detectada
process_new_application() {
  local app_name="$1"
  local app_path="$2"
  
  # Si el agente está inactivo, no procesar nuevas aplicaciones
  if [ "$AGENT_STATUS" = "inactive" ]; then
    log 1 "Agente inactivo. Detectada nueva aplicación $app_name pero no se tomará ninguna acción"
    return 0
  fi
  
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
  
  # Mostrar diálogo informativo inicial
  local dialog_text="Se ha detectado la instalación de una nueva aplicación: $app_name\n\nVersión: $app_version\nDesarrollador: $vendor\nRuta: $app_path\nSHA256: $sha256\nUsuario: $username"
  show_dialog "Instalación Detectada" "$dialog_text" "caution"
  
  # En modo pasivo, solo registrar la aplicación sin bloquearla
  if [ "$AGENT_MODE" = "passive" ]; then
    log 1 "Modo pasivo. Detectada nueva aplicación $app_name, se registrará sin bloquear"
    # Verificar si el software está autorizado (solo para registrar en el servidor)
    verify_software "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature"
    return 0
  fi
  
  # En modo activo, restringir permisos de ejecución temporalmente
  log 1 "Modo activo. Restringiendo ejecución de $app_name temporalmente"
  restrict_app_execution "$app_path"
  
  # Verificar primero si el software ya existe en la base de datos
  if check_software_database "$app_name" "$app_version" "$device_id"; then
    # Software encontrado en la base de datos
    local db_status=$(echo "$response" | jq -r '.status // "unknown"')
    local software_id=$(echo "$response" | jq -r '.softwareId // ""')
    
    if [ "$db_status" = "approved" ] || [ "$db_status" = "whitelist" ]; then
      # Software ya aprobado en la base de datos
      log 1 "$app_name está en la base de datos y aprobado. Restaurando permisos"
      restore_app_execution "$app_path"
      log 1 "Aplicación $app_name aprobada y lista para usar"
    elif [ "$db_status" = "rejected" ] || [ "$db_status" = "blacklist" ] || [ "$db_status" = "denied" ]; then
      # Software ya rechazado en la base de datos
      log 1 "$app_name está en la base de datos y rechazado. Eliminando"
      
      # Obtener razón de rechazo si está disponible
      local rejection_reason=$(echo "$response" | jq -r '.reason // "No cumple con las políticas de seguridad"')
      
      # Mostrar mensaje al usuario
      show_dialog "Software No Autorizado" "El software $app_name no está permitido por motivos de seguridad:\n\n$rejection_reason\n\nLa aplicación será eliminada." "stop"
      
      # Eliminar la aplicación
      if delete_application "$app_path"; then
        log 1 "Aplicación $app_name eliminada correctamente"
      else
        log 1 "Error al eliminar la aplicación $app_name"
        show_dialog "Error" "No se pudo eliminar completamente la aplicación. Por favor, contacte con soporte técnico." "stop"
      fi
    else
      # Software en estado pendiente o desconocido
      log 1 "$app_name está en la base de datos con estado $db_status. Manteniendo bloqueada"
      show_dialog "Software Pendiente" "El software $app_name requiere aprobación. Se mantiene bloqueado hasta completar el análisis de seguridad" "caution"
    fi
  else
    # Software no encontrado en la base de datos, se requiere verificación completa
    show_dialog "Verificación de Software" "El software $app_name no está registrado. Se iniciará el proceso de verificación.\n\nEste proceso tomará aproximadamente 10 segundos" "note"
    
    # Verificar si el software está autorizado con el proceso completo
    local verification_result
    verify_software "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature"
    verification_result=$?
    
    if [ $verification_result -eq 0 ]; then
      # Software aprobado (whitelist)
      log 1 "$app_name ha sido aprobado. Restaurando permisos de ejecución"
      restore_app_execution "$app_path"
    elif [ $verification_result -eq 2 ]; then
      # Software rechazado (blacklist)
      log 1 "$app_name ha sido rechazado. Eliminando"
      
      # Intentar obtener la razón del rechazo desde la respuesta
      local reason="No cumple con las políticas de seguridad"
      if [[ "$response" == *"\"reason\""* ]] && command -v jq &> /dev/null; then
        reason=$(echo "$response" | jq -r '.reason // "No cumple con las políticas de seguridad"')
      fi
      
      # Informar al usuario
      show_dialog "Software No Permitido" "La instalación de $app_name ha sido bloqueada.\n\nRazón: $reason" "stop"
      
      # Eliminar la aplicación
      if delete_application "$app_path"; then
        log 1 "Aplicación $app_name eliminada correctamente"
      else
        log 1 "Error al eliminar la aplicación $app_name"
        show_dialog "Error" "No se pudo eliminar completamente la aplicación. Por favor, contacte con soporte técnico." "stop"
      fi
    else
      # Software en estado pendiente
      log 1 "$app_name necesita aprobación manual. Manteniendo bloqueada"
      show_dialog "Software Pendiente" "El software $app_name requiere aprobación. Se mantiene bloqueado hasta que se complete el análisis de seguridad" "caution"
      
      # Registrar en la lista de pendientes
      add_to_pending_list "$app_name" "$app_version" "$app_path" "$software_id"
    fi
  fi
}

# Verificar si el software ya existe en la base de datos
check_software_database() {
  local software_name="$1"
  local version="$2"
  local device_id="$3"
  
  log 2 "Verificando si $software_name $version ya existe en la base de datos..."
  
  # Construir el endpoint para la consulta
  local endpoint="${BACKEND_URL}/software/exists?name=${software_name}&version=${version}&deviceId=${device_id}"
  
  # Realizar la consulta al servidor
  local response=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    "$endpoint")
  
  # Analizar respuesta (requiere jq)
  if command -v jq &> /dev/null; then
    # Extraer información relevante
    local exists=$(echo "$response" | jq -r '.exists // false')
    local software_id=$(echo "$response" | jq -r '.softwareId // ""')
    local status=$(echo "$response" | jq -r '.status // "unknown"')
    
    if [ "$exists" = "true" ] && [ -n "$software_id" ]; then
      log 2 "Software encontrado en la base de datos. ID: $software_id, Estado: $status"
      return 0
    else
      log 2 "Software no encontrado en la base de datos"
      return 1
    fi
  else
    log 1 "Error: jq no está instalado"
    return 2
  fi
}

# Función principal que ejecuta el ciclo de monitoreo
run_monitor() {
  log 1 "Iniciando monitor de instalaciones..."
  
  # Configurar carpetas necesarias
  setup_quarantine
  setup_config_dir
  
  # Cargar o crear configuración
  load_or_create_config
  
  # Verificar actualizaciones del agente
  check_for_updates
  
  # Variables para controlar el estado del monitor
  local monitoring_active=true
  local initial_apps=""
  
  # Mostrar notificación de inicio
  show_notification "Monitor de Instalaciones" "Monitor de instalaciones iniciado"
  
  # Iniciar bucle principal que permanece activo incluso cuando el agente está inactivo
  while true; do
    # Comprobar estado actual del agente
    if [ "$AGENT_STATUS" = "inactive" ] && [ "$monitoring_active" = "true" ]; then
      log 1 "Agente configurado como inactivo. Entrando en modo espera"
      monitoring_active=false
      show_notification "Monitor de Instalaciones" "Agente inactivo - modo espera activado"
    elif [ "$AGENT_STATUS" = "active" ] && [ "$monitoring_active" = "false" ]; then
      log 1 "Agente reactivado. Retomando monitorización"
      monitoring_active=true
      show_notification "Monitor de Instalaciones" "Agente reactivado en modo $AGENT_MODE"
      # Reinicializar la lista de aplicaciones para evitar alertas de aplicaciones instaladas durante inactividad
      initial_apps=$(get_current_apps)
    fi
    
    # Si el agente está activo, realizar el monitoreo normal
    if [ "$monitoring_active" = "true" ]; then
      # Si es la primera ejecución, inicializar la lista de aplicaciones
      if [ -z "$initial_apps" ]; then
        initial_apps=$(get_current_apps)
        log 1 "Se han detectado $(echo "$initial_apps" | wc -l | tr -d ' ') aplicaciones iniciales"
      fi
      
      # Verificar aplicaciones pendientes
      check_pending_applications
      
      # Obtener lista actual de aplicaciones
      local current_apps=$(get_current_apps)
      
      # Buscar nuevas aplicaciones
      while IFS= read -r app; do
        if [ -n "$app" ] && ! app_exists "$app" "$initial_apps"; then
          log 1 "Nueva aplicación detectada: $app"
          
          # Extraer nombre sin extensión .app
          local app_name="${app%.app}"
          
          # Procesar la nueva aplicación
          process_new_application "$app_name" "$APPS_DIRECTORY/$app"
          
          # Actualizar lista de aplicaciones conocidas
          initial_apps=$(echo -e "$initial_apps\n$app")
        fi
      done < <(echo "$current_apps")
      
      # Esperar antes del siguiente escaneo (intervalo normal para monitoreo activo)
      sleep $SCAN_INTERVAL
    else
      # En modo inactivo, esperar el mismo intervalo que el daemon de sincronización
      sleep 60
    fi
  done
}

# Enviar ping al servidor para actualizar estado de actividad
ping_server() {
  local device_id=$(get_device_id)
  local username=$(get_username)
  
  log 2 "Enviando ping al servidor..."
  
  # Construir payload con información del agente
  local payload="{\"deviceId\":\"$device_id\",\"employeeEmail\":\"$username@example.com\",\"status\":\"$AGENT_STATUS\"}"
  
  # Enviar ping al servidor
  local ping_response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    -d "$payload" \
    "$PING_ENDPOINT")
  
  # Verificar si la respuesta fue exitosa
  if [[ "$ping_response" == *"\"success\":true"* ]]; then
    # Actualizar la última sincronización exitosa
    LAST_SYNC_TIME=$(date +%s)
    
    # Verificar si se debe actualizar el agente
    if [[ "$ping_response" == *"\"shouldUpdate\":true"* ]]; then
      log 1 "El servidor indica que se debe actualizar el agente"
      check_for_updates
    fi
    
    return 0
  else
    log 1 "Error al enviar ping al servidor"
    return 1
  fi
}

# Sincronizar configuración periódicamente en segundo plano (cada minuto)
start_sync_daemon() {
  (
    while true; do
      # Registrar tiempo de inicio de ciclo
      local cycle_start=$(date +%s)
      
      # Sincronizar configuración con el servidor
      sync_config_with_server
      
      # Enviar ping al servidor para actualizar estado de actividad
      # Siempre enviamos el ping, incluso si el agente está inactivo
      ping_result=$(ping_server)
      ping_exit_code=$?
      
      # Registrar resultado del ping
      if [ $ping_exit_code -eq 0 ]; then
        log 1 "Ping exitoso: Estado del agente actualizado en el servidor"
        # Resetear el tiempo de fallo de autenticación si el ping fue exitoso
        AUTH_FAILURE_TIME=0
        AUTH_FAILURE_REPORTED=0
      else
        log 1 "Error en ping: No se pudo actualizar el estado del agente"
      fi
      
      # Verificar actualizaciones si está habilitado
      if [ "$AGENT_AUTO_UPDATE" = "true" ]; then
        check_for_updates
      fi
      
      # Calcular tiempo transcurrido en este ciclo
      local cycle_end=$(date +%s)
      local cycle_duration=$((cycle_end - cycle_start))
      
      # Calcular tiempo de espera para mantener intervalo preciso
      local wait_time=$((PING_INTERVAL - cycle_duration))
      
      # Asegurar que wait_time no sea negativo
      if [ $wait_time -lt 1 ]; then
        wait_time=1
      fi
      
      log 1 "Próximo ping en $wait_time segundos..."
      
      # Esperar para la siguiente sincronización (ajustando para mantener intervalo constante)
      sleep $wait_time
    done
  ) &
  
  # Registrar el PID del daemon para debugging
  SYNC_DAEMON_PID=$!
  log 2 "Daemon de sincronización iniciado con PID: $SYNC_DAEMON_PID"
}

# Función para restringir permisos de ejecución de una aplicación
restrict_app_execution() {
  local app_path="$1"
  local macos_dir="${app_path}/Contents/MacOS"
  local metadata_dir="${app_path}/Contents/.softcheck"
  
  log 1 "Restringiendo permisos de ejecución para: $app_path"
  
  # Verificar que la aplicación existe y es legible
  if [ ! -d "$app_path" ]; then
    log 1 "ERROR: La aplicación no existe o no es un directorio: $app_path"
    return 1
  fi
  
  # Crear directorio para metadata si no existe
  mkdir -p "$metadata_dir" 2>/dev/null
  if [ ! -d "$metadata_dir" ]; then
    log 1 "ERROR: No se pudo crear directorio de metadatos: $metadata_dir"
    return 1
  fi
  
  # Verificar si el directorio MacOS existe
  if [ ! -d "$macos_dir" ]; then
    log 1 "ERROR: Directorio MacOS no encontrado en: $app_path"
    return 1
  fi
  
  # Listar contenido del directorio MacOS para diagnóstico
  log 1 "Contenido del directorio MacOS:"
  ls -la "$macos_dir" | while read -r line; do
    log 1 "  $line"
  done
  
  # Primero guardar permisos originales de los ejecutables en MacOS
  log 1 "Guardando permisos originales de ejecutables en MacOS..."
  find "$macos_dir" -type f -exec ls -la {} \; > "${metadata_dir}/original_ls"
  
  # Guardar permisos usando stat para cada archivo ejecutable
  find "$macos_dir" -type f | while read -r file; do
    # Verificar si es ejecutable
    if [ -x "$file" ]; then
      # Guardar permisos usando varios métodos para mayor seguridad
      local perms=$(stat -f "%p" "$file")
      local user_id=$(stat -f "%u" "$file")
      local group_id=$(stat -f "%g" "$file")
      echo "$file:$perms:$user_id:$group_id" >> "${metadata_dir}/exec_perms"
      log 1 "Archivo ejecutable encontrado: $file (permisos: $perms)"
    fi
  done
  
  # Obtener el nombre del ejecutable principal
  local main_binary=$(find "$macos_dir" -type f -perm +111 | head -1)
  if [ -n "$main_binary" ]; then
    log 1 "Ejecutable principal detectado: $main_binary"
    echo "$main_binary" > "${metadata_dir}/main_binary"
  else
    log 1 "ADVERTENCIA: No se encontró ejecutable principal"
  fi
  
  # Guardar atributos extendidos
  xattr -l "$app_path" > "${metadata_dir}/app_xattr" 2>/dev/null
  
  # Quitar permisos de ejecución de archivos en MacOS
  log 1 "Quitando permisos de ejecución a archivos en MacOS..."
  chmod -R a-x "$macos_dir"
  
  log 1 "Permisos restringidos para: $app_path"
  return 0
}

# Función para restaurar permisos de ejecución de una aplicación
restore_app_execution() {
  local app_path="$1"
  local macos_dir="${app_path}/Contents/MacOS"
  local metadata_dir="${app_path}/Contents/.softcheck"
  
  log 1 "Restaurando permisos de ejecución para: $app_path"
  
  # Verificar directorio de la aplicación
  if [ ! -d "$app_path" ]; then
    log 1 "ERROR: La aplicación no existe: $app_path"
    return 1
  fi
  
  # Verificar directorio MacOS
  if [ ! -d "$macos_dir" ]; then
    log 1 "ERROR: Directorio MacOS no encontrado: $macos_dir"
    return 1
  fi
  
  # Verificar directorio de metadatos
  if [ ! -d "$metadata_dir" ]; then
    log 1 "ERROR: Directorio de metadatos no encontrado: $metadata_dir"
    # Aplicar permisos de forma directa como fallback
    log 1 "Aplicando permisos de ejecución estándar..."
    chmod -R +x "$macos_dir"
    return 1
  fi
  
  # Mostrar el estado actual de los archivos para diagnóstico
  log 1 "Estado actual de archivos en MacOS antes de restaurar:"
  ls -la "$macos_dir" | while read -r line; do
    log 1 "  $line"
  done
  
  # Restaurar permisos usando el archivo de permisos
  if [ -f "${metadata_dir}/exec_perms" ]; then
    log 1 "Restaurando permisos específicos..."
    while IFS=: read -r file perms uid gid; do
      if [ -f "$file" ]; then
        # Restaurar permisos, usuario y grupo
        log 1 "Restaurando permisos para $file: $perms"
        chmod "$perms" "$file"
        chown "$uid:$gid" "$file" 2>/dev/null
      else
        log 1 "ADVERTENCIA: Archivo no encontrado: $file"
      fi
    done < "${metadata_dir}/exec_perms"
  else
    log 1 "Archivo de permisos específicos no encontrado, usando método alternativo"
  fi
  
  # Si no se restauraron los permisos correctamente, usar el método alternativo
  local main_binary=""
  if [ -f "${metadata_dir}/main_binary" ]; then
    main_binary=$(cat "${metadata_dir}/main_binary")
    if [ -f "$main_binary" ]; then
      log 1 "Asegurando permisos para el ejecutable principal: $main_binary"
      chmod 755 "$main_binary"
    fi
  fi
  
  # Aplicar permisos de ejecución a todo el directorio MacOS como medida adicional
  log 1 "Aplicando permisos de ejecución al directorio MacOS..."
  chmod -R +x "$macos_dir"
  
  # Eliminar cualquier atributo de cuarentena
  log 1 "Eliminando atributos de cuarentena..."
  xattr -d com.apple.quarantine "$app_path" 2>/dev/null
  
  # Registrar la aplicación en LaunchServices
  log 1 "Registrando aplicación en LaunchServices..."
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path" 2>/dev/null
  
  # Añadir un delay para que los cambios se propaguen
  sleep 1
  
  # Estado final de los archivos para diagnóstico
  log 1 "Estado final de archivos en MacOS después de restaurar:"
  ls -la "$macos_dir" | while read -r line; do
    log 1 "  $line"
  done
  
  # Limpiar archivos de metadatos
  rm -rf "$metadata_dir"
  
  log 1 "Permisos restaurados para: $app_path"
  return 0
}

# --- Iniciar el agente ---
# Establecer hora de inicio para sincronización más precisa
SYNC_START_TIME=$(date +%s)
PING_INTERVAL=60  # Intervalo de ping en segundos

# Iniciar el daemon de sincronización
start_sync_daemon

# Mostrar información inicial del agente
print_agent_settings

# Ejecutar el monitor de instalaciones
run_monitor 