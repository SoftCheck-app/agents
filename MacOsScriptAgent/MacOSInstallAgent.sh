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
SCAN_INTERVAL=1  # segundos entre escaneos - verificar aplicaciones pendientes cada 10 segundos
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
LAST_STATUS_NOTIFICATION=0 # Tiempo de la última notificación de estado

# Variables globales para almacenar información de la IA
LAST_IA_REASON=""
LAST_IA_DETAILED_REASON=""

# Variable para controlar el último tiempo de sincronización exitosa
LAST_SYNC_TIME=0

# Función para sanitizar texto de la IA para mostrar en diálogos
sanitize_ia_text() {
  local text="$1"
  
  # Si el texto está vacío o es null, retornar vacío
  if [ -z "$text" ] || [ "$text" = "null" ]; then
    echo ""
    return
  fi
  
  # Limpiar caracteres problemáticos y limitiar longitud
  # Quitar comillas dobles problemáticas y saltos de línea literales
  local clean_text=$(echo "$text" | sed 's/\\n/ /g' | sed 's/\\"/"/g' | sed 's/^"//g' | sed 's/"$//g')
  
  # Limitar longitud del mensaje para evitar diálogos muy largos (máximo 500 caracteres)
  if [ ${#clean_text} -gt 500 ]; then
    clean_text="${clean_text:0:497}..."
  fi
  
  # Si el texto sigue vacío después de la limpieza, usar mensaje por defecto
  if [ -z "$clean_text" ]; then
    echo "No se proporcionó información adicional"
  else
    echo "$clean_text"
  fi
}

# Función para escapar caracteres especiales en JSON
escape_json_value() {
  local value="$1"
  
  # Si el valor está vacío, retornar comillas vacías
  if [ -z "$value" ]; then
    echo ""
    return
  fi
  
  # Escapar caracteres especiales para JSON
  # Primero las barras invertidas, luego las comillas dobles
  local escaped_value=$(echo "$value" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\n/\\n/g' | sed 's/\r/\\r/g' | sed 's/\t/\\t/g')
  
  echo "$escaped_value"
}

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
  
  # Verificar que la aplicación existe
  if [ ! -d "$app_path" ]; then
    log 2 "ADVERTENCIA: Aplicación no existe: $app_path" >&2
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    return 1
  fi
  
  local date_str=$(stat -f "%SB" -t "%Y-%m-%dT%H:%M:%SZ" "$app_path" 2>/dev/null)
  
  # Si no hay fecha o es inválida, usar fecha actual
  if [ -z "$date_str" ] || [ "$date_str" = "null" ]; then
    log 2 "ADVERTENCIA: No se pudo obtener fecha de instalación para $app_path" >&2
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    return 1
  fi
  
  # Validar que la fecha no sea muy antigua (anterior a 1990) o muy futura
  local year=$(echo "$date_str" | cut -d'-' -f1 2>/dev/null)
  if [ -n "$year" ] && [ "$year" -ge 1990 ] && [ "$year" -le 2030 ]; then
    echo "$date_str"
    return 0
  else
    log 2 "ADVERTENCIA: Fecha de instalación inválida para $app_path: $date_str" >&2
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    return 1
  fi
}

# Función común para construir el JSON de software con todos los datos necesarios
build_software_json() {
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
  local software_id="${11:-}"
  
  # Escapar todos los valores de texto para JSON
  local escaped_app_name=$(escape_json_value "$app_name")
  local escaped_app_version=$(escape_json_value "$app_version")
  local escaped_app_path=$(escape_json_value "$app_path")
  local escaped_sha256=$(escape_json_value "$sha256")
  local escaped_username=$(escape_json_value "$username")
  local escaped_device_id=$(escape_json_value "$device_id")
  local escaped_vendor=$(escape_json_value "$vendor")
  local escaped_install_date=$(escape_json_value "$install_date")
  local escaped_software_id=$(escape_json_value "$software_id")
  
  # Crear objeto JSON base con todos los datos escapados
  local json="{
    \"device_id\": \"$escaped_device_id\",
    \"user_id\": \"$escaped_username\",
    \"software_name\": \"$escaped_app_name\",
    \"version\": \"$escaped_app_version\",
    \"vendor\": \"$escaped_vendor\",
    \"install_date\": \"$escaped_install_date\",
    \"install_path\": \"$escaped_app_path\",
    \"install_method\": \"manual\",
    \"last_executed\": null,
    \"is_running\": $is_running,
    \"digital_signature\": $digital_signature,
    \"is_approved\": false,
    \"detected_by\": \"macos_agent\",
    \"sha256\": \"$escaped_sha256\",
    \"notes\": null"
  
  # Añadir softwareId si se proporciona (para consultas de estado)
  if [ -n "$software_id" ]; then
    json="$json,\"softwareId\": \"$escaped_software_id\""
  fi
  
  json="$json}"
  
  # Debug: verificar que el JSON es válido
  if command -v jq &> /dev/null; then
    if ! echo "$json" | jq empty 2>/dev/null; then
      log 1 "ERROR: JSON de software construido es inválido para $escaped_app_name"
      log 2 "DEBUG - JSON inválido: $json"
      # Retornar un JSON mínimo válido como fallback
      echo "{\"software_name\":\"$escaped_app_name\",\"version\":\"$escaped_app_version\",\"device_id\":\"$escaped_device_id\"}"
      return 1
    fi
  fi
  
  echo "$json"
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
  
  # DEBUG: Mostrar valores antes de construir JSON
  log 1 "DEBUG - Valores originales para $app_name:"
  log 1 "DEBUG - app_name: '$app_name'"
  log 1 "DEBUG - app_version: '$app_version'"
  log 1 "DEBUG - app_path: '$app_path'"
  log 1 "DEBUG - sha256: '$sha256'"
  log 1 "DEBUG - username: '$username'"
  log 1 "DEBUG - device_id: '$device_id'"
  log 1 "DEBUG - vendor: '$vendor'"
  log 1 "DEBUG - install_date: '$install_date'"
  log 1 "DEBUG - is_running: '$is_running'"
  log 1 "DEBUG - digital_signature: '$digital_signature'"
  
  # Crear objeto JSON usando la función común
  local json=$(build_software_json "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature")
  
  # DEBUG: Mostrar JSON construido
  log 1 "DEBUG - JSON construido para enviar:"
  log 1 "DEBUG - JSON: $json"
  
  # Verificar que el JSON es válido antes de enviarlo
  if command -v jq &> /dev/null; then
    if ! echo "$json" | jq empty 2>/dev/null; then
      log 1 "ERROR: JSON construido es inválido para $app_name"
      log 1 "ERROR: JSON inválido: $json"
      return 1
    else
      log 1 "DEBUG - JSON validado correctamente con jq"
    fi
  fi
  
  # Enviar solicitud de verificación y obtener respuesta
  local temp_response_file=$(mktemp)
  local temp_headers_file=$(mktemp)
  
  log 1 "DEBUG - Enviando petición POST a: $VERIFICATION_ENDPOINT"
  
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
  local curl_error=$(cat "$temp_headers_file")
  
  # DEBUG: Mostrar respuesta del servidor
  log 1 "DEBUG - curl exit code: $curl_exit_code"
  log 1 "DEBUG - curl error: $curl_error"
  log 1 "DEBUG - Respuesta del servidor: $response"
  
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
      local rejection_reason=$(echo "$response" | jq -r '.reason // ""')
      local is_rejected=$(echo "$response" | jq -r '.isRejected // false')
      local auth_status=$(echo "$response" | jq -r '.authorizationStatus // ""')
      local auth_result=$(echo "$response" | jq -r '.authorizationResult // ""')
      
      # Capturar razón detallada de la IA si está disponible
      local razon_de_la_IA=$(echo "$response" | jq -r '.razon_de_la_IA // ""')
      if [ -n "$razon_de_la_IA" ] && [ "$razon_de_la_IA" != "null" ]; then
        LAST_IA_DETAILED_REASON="$razon_de_la_IA"
        log 2 "Razón detallada de la IA capturada: '$razon_de_la_IA'"
        log 2 "Longitud de la razón de la IA: ${#razon_de_la_IA} caracteres"
      else
        log 2 "No se encontró razón detallada de la IA válida en la respuesta"
        LAST_IA_DETAILED_REASON=""
      fi
      
      # Verificar si hay información de autorización en la respuesta
      if [[ "$response" == *"autorizado"* ]]; then
        local autorizado=$(echo "$response" | jq -r '.autorizado // null')
        if [ "$autorizado" = "0" ] || [ "$autorizado" = "false" ]; then
          status="rejected"
          if [[ "$response" == *"razon"* ]]; then
            rejection_reason=$(echo "$response" | jq -r '.razon // "No cumple con las políticas de seguridad"')
            LAST_IA_REASON="$rejection_reason"
          fi
          log 2 "Software rechazado por autorización. Razón: $rejection_reason"
        elif [ "$autorizado" = "1" ] || [ "$autorizado" = "true" ]; then
          status="approved"
          if [[ "$response" == *"razon"* ]]; then
            local approval_reason=$(echo "$response" | jq -r '.razon // "Software verificado correctamente"')
            LAST_IA_REASON="$approval_reason"
          fi
          log 2 "Software aprobado por autorización"
        else
          status="pending"
        fi
      else
        # Detectar si fue explícitamente rechazada por otros medios
        if [ "$is_approved" = "true" ]; then
          status="approved"
          LAST_IA_REASON="$rejection_reason"
        elif [ "$is_rejected" = "true" ] || [ -n "$rejection_reason" ] || [[ "$response" == *"\"rejected\""* ]]; then
          status="rejected"
          LAST_IA_REASON="$rejection_reason"
          log 2 "Software rechazado. Razón: $rejection_reason"
        else
          status="pending"
        fi
      fi
      
      log 2 "Software ID: $software_id, IsApproved: $is_approved, IsRejected: $is_rejected, Mapped Status: $status"
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
  elif [ "$status" = "blacklist" ] || [ "$status" = "rejected" ] || [ "$status" = "denied" ]; then
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
  
  # Verificar que la aplicación existe antes de añadirla a la lista
  if [ ! -d "$app_path" ]; then
    log 1 "ADVERTENCIA: No se puede añadir aplicación inexistente a lista de pendientes: $app_path"
    return 1
  fi
  
  # Verificar que sea una aplicación macOS válida
  if [ ! -d "$app_path/Contents" ]; then
    log 1 "ADVERTENCIA: $app_path no es una aplicación macOS válida, no se añadirá a pendientes"
    return 1
  fi
  
  # Obtener todos los datos necesarios para futuras consultas
  local username=$(get_username)
  local device_id=$(get_device_id)
  local vendor=$(get_app_vendor "$app_path")
  local install_date=$(get_install_date "$app_path")
  local is_running=$(is_app_running "$app_name")
  local digital_signature=$(check_digital_signature "$app_path")
  local sha256="no_disponible"
  
  # Calcular SHA256 si es posible
  local main_executable=$(find_main_executable "$app_path")
  if [ -n "$main_executable" ]; then
    sha256=$(calculate_sha256 "$main_executable")
  fi
  
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
      \"sha256\": \"$sha256\",
      \"username\": \"$username\",
      \"device_id\": \"$device_id\",
      \"vendor\": \"$vendor\",
      \"install_date\": \"$install_date\",
      \"is_running\": \"$is_running\",
      \"digital_signature\": \"$digital_signature\",
      \"timestamp\": $timestamp
    }"
    
    # Insertar el nuevo registro en el array
    local updated_json=$(echo "$current_json" | jq ". += [$new_entry]")
    echo "$updated_json" > "$PENDING_APPS_FILE"
    
    log 2 "Aplicación $app_name añadida a la lista de pendientes con todos los datos"
  else
    log 1 "No se pudo añadir a la lista de pendientes: jq no está instalado"
  fi
}

# Limpiar aplicaciones inexistentes de la lista de pendientes
clean_invalid_pending_apps() {
  log 2 "Limpiando aplicaciones inexistentes de la lista de pendientes..."
  
  # Verificar si hay aplicaciones pendientes
  if [ ! -f "$PENDING_APPS_FILE" ]; then
    log 2 "No hay archivo de aplicaciones pendientes"
    return 0
  fi
  
  # Leer la lista de aplicaciones pendientes
  local pending_apps=$(cat "$PENDING_APPS_FILE")
  
  # Si no hay jq instalado, no podemos procesar el JSON
  if ! command -v jq &> /dev/null; then
    log 1 "Error: jq no está instalado, no se pueden limpiar aplicaciones pendientes"
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
  
  if [ "$count" -eq 0 ]; then
    log 2 "No hay aplicaciones pendientes que limpiar"
    return 0
  fi
  
  log 2 "Verificando $count aplicaciones pendientes..."
  
  # Array para almacenar aplicaciones válidas
  local valid_apps="[]"
  
  # Iterar sobre cada aplicación pendiente
  for i in $(seq 0 $(($count - 1))); do
    local app_path=$(echo "$pending_apps" | jq -r ".[$i].app_path")
    local app_name=$(echo "$pending_apps" | jq -r ".[$i].app_name")
    
    # Verificar si la aplicación existe físicamente
    if [ -d "$app_path" ] && [ -d "$app_path/Contents" ]; then
      # Aplicación válida, mantenerla
      local app_entry=$(echo "$pending_apps" | jq ".[$i]")
      valid_apps=$(echo "$valid_apps" | jq ". += [$app_entry]")
      log 2 "Manteniendo aplicación válida: $app_name"
    else
      # Aplicación inexistente, eliminarla
      log 1 "Eliminando aplicación inexistente de la lista: $app_name ($app_path)"
    fi
  done
  
  # Guardar la lista actualizada
  echo "$valid_apps" > "$PENDING_APPS_FILE"
  
  # Contar aplicaciones después de la limpieza
  local new_count=$(echo "$valid_apps" | jq '. | length')
  local removed_count=$((count - new_count))
  
  if [ $removed_count -gt 0 ]; then
    log 1 "Se eliminaron $removed_count aplicaciones inexistentes de la lista de pendientes"
  else
    log 2 "No se encontraron aplicaciones inexistentes que eliminar"
  fi
}

# Verificar estado de aplicaciones pendientes
check_pending_applications() {
  log 2 "Verificando aplicaciones pendientes..."
  
  # Primero limpiar aplicaciones inexistentes
  clean_invalid_pending_apps
  
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
  
  if [ "$count" -eq 0 ]; then
    log 2 "No hay aplicaciones pendientes"
    return 0
  fi
  
  # Si hay aplicaciones pendientes, mostrar notificación de estado cada 30 segundos
  local now=$(date +%s)
  # Verificar si han pasado 30 segundos desde la última notificación de estado
  if [ -z "$LAST_STATUS_NOTIFICATION" ] || [ $((now - LAST_STATUS_NOTIFICATION)) -ge 30 ]; then
    # show_notification "Verificación en Proceso" "Analizando $count aplicación(es)... El proceso puede tardar hasta 20 segundos"
    LAST_STATUS_NOTIFICATION=$now
  fi
  log 2 "$count aplicaciones pendientes encontradas"
  
  # Array para almacenar IDs de aplicaciones a eliminar de la lista
  local apps_to_remove=()
  
  # Iterar sobre cada aplicación pendiente
  for i in $(seq 0 $(($count - 1))); do
    local software_id=$(echo "$pending_apps" | jq -r ".[$i].software_id")
    local app_name=$(echo "$pending_apps" | jq -r ".[$i].app_name")
    local app_version=$(echo "$pending_apps" | jq -r ".[$i].app_version")
    local app_path=$(echo "$pending_apps" | jq -r ".[$i].app_path")
    local sha256=$(echo "$pending_apps" | jq -r ".[$i].sha256 // \"no_disponible\"")
    local username=$(echo "$pending_apps" | jq -r ".[$i].username // \"\"")
    local device_id=$(echo "$pending_apps" | jq -r ".[$i].device_id // \"\"")
    local vendor=$(echo "$pending_apps" | jq -r ".[$i].vendor // \"desconocido\"")
    local install_date=$(echo "$pending_apps" | jq -r ".[$i].install_date // \"null\"")
    local is_running=$(echo "$pending_apps" | jq -r ".[$i].is_running // \"false\"")
    local digital_signature=$(echo "$pending_apps" | jq -r ".[$i].digital_signature // \"false\"")
    
    # Si falta información crítica, obtenerla dinámicamente
    if [ -z "$username" ] || [ "$username" = "null" ]; then
      username=$(get_username)
    fi
    if [ -z "$device_id" ] || [ "$device_id" = "null" ]; then
      device_id=$(get_device_id)
    fi
    
    log 2 "Re-verificando estado de $app_name (ID: $software_id)..."
    
    # Primero intentar consultar el estado de autorización directamente con todos los datos
    local auth_status_result=""
    if check_authorization_status "$software_id" "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature"; then
      auth_status_result=$(check_authorization_status "$software_id" "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature")
      
      # Procesar resultado de la consulta de autorización
      if [[ "$auth_status_result" == "approved"* ]]; then
        # Software aprobado
        log 1 "$app_name ha sido aprobado. Restaurando permisos de ejecución..."
        
        # Extraer razón si está incluida en el resultado
        local ia_reason=""
        if [[ "$auth_status_result" == *":"* ]]; then
          ia_reason="${auth_status_result#approved:}"
          # Sanitizar la razón obtenida
          ia_reason=$(sanitize_ia_text "$ia_reason")
        fi
        
        # Construir mensaje con razón de la IA si está disponible
        local approval_message="El análisis de ciberseguridad de $app_name ha finalizado.\n\nRESULTADO: APROBADO ✅\n\nLa aplicación ha superado todos los controles de seguridad y políticas empresariales."
        
        if [ -n "$ia_reason" ] && [ "$ia_reason" != "null" ]; then
          approval_message="$approval_message\n\nAnálisis de la IA: $ia_reason"
        fi
        
        approval_message="$approval_message\n\nSe están restaurando los permisos de ejecución."
        
        show_dialog "Análisis Completado - APROBADO" "$approval_message" "note"
        
        if restore_app_execution "$app_path"; then
          log 1 "Permisos restaurados para $app_name"
          # show_notification "Software Aprobado" "$app_name está listo para usar"
          apps_to_remove+=("$software_id")
        else
          show_dialog "Error de Restauración" "El software $app_name ha sido aprobado, pero hubo un problema al restaurar sus permisos." "stop"
        fi
      continue
      elif [[ "$auth_status_result" == rejected:* ]]; then
        # Software rechazado
        local rejection_reason="${auth_status_result#rejected:}"
        if [ -z "$rejection_reason" ] || [ "$rejection_reason" = "null" ]; then
          rejection_reason="No cumple con las políticas de seguridad"
        else
          # Sanitizar la razón obtenida del resultado de autorización
          rejection_reason=$(sanitize_ia_text "$rejection_reason")
          if [ -z "$rejection_reason" ]; then
            rejection_reason="No cumple con las políticas de seguridad"
          fi
        fi
        
        log 1 "$app_name ha sido rechazado. Eliminando..."
        
        local denial_message="El análisis de ciberseguridad de $app_name ha finalizado.\n\nRESULTADO: DENEGADO ❌\n\nRazón: $rejection_reason\n\nLa aplicación será eliminada del sistema por motivos de seguridad."
        
        show_dialog "Análisis Completado - DENEGADO" "$denial_message" "stop"
        
        if delete_application "$app_path"; then
          log 1 "Aplicación $app_name eliminada correctamente"
          # show_notification "Software Eliminado" "$app_name ha sido eliminado por seguridad"
          apps_to_remove+=("$software_id")
        else
          show_dialog "Error de Eliminación" "El software $app_name ha sido rechazado, pero hubo un problema al eliminarlo." "stop"
        fi
        continue
      elif [[ "$auth_status_result" == "pending" ]]; then
        # Aún pendiente
        log 2 "$app_name sigue pendiente de autorización"
      continue
      fi
    fi
    
    # Si la consulta directa falla, usar el método tradicional de re-verificación
    log 2 "Usando método de re-verificación tradicional para $app_name..."
    
    # Usar los datos almacenados para re-verificar el software
    # Solo obtener dinámicamente los datos que pueden cambiar (is_running)
    local current_is_running=$(is_app_running "$app_name")
    
    # Volver a verificar el software usando todos los datos originales
    local verification_result
    verify_software "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$current_is_running" "$digital_signature"
    verification_result=$?
    
    # Actuar según el resultado
    if [ $verification_result -eq 0 ]; then
      # Software aprobado
      log 1 "$app_name ha sido aprobado. Restaurando permisos de ejecución..."
      
      # Construir mensaje con razón de la IA si está disponible
      local approval_message="El análisis de ciberseguridad de $app_name ha finalizado.\n\nRESULTADO: APROBADO ✅\n\nLa aplicación ha superado todos los controles de seguridad y políticas empresariales."
      
      if [ -n "$LAST_IA_DETAILED_REASON" ] && [ "$LAST_IA_DETAILED_REASON" != "null" ]; then
        local ia_analysis=$(sanitize_ia_text "$LAST_IA_DETAILED_REASON")
        if [ -n "$ia_analysis" ]; then
          approval_message="$approval_message\n\nAnálisis de la IA: $ia_analysis"
        fi
      elif [ -n "$LAST_IA_REASON" ] && [ "$LAST_IA_REASON" != "null" ]; then
        local ia_evaluation=$(sanitize_ia_text "$LAST_IA_REASON")
        if [ -n "$ia_evaluation" ]; then
          approval_message="$approval_message\n\nEvaluación: $ia_evaluation"
        fi
      fi
      
      approval_message="$approval_message\n\nSe están restaurando los permisos de ejecución."
      
      show_dialog "Análisis Completado - APROBADO" "$approval_message" "note"
      
      if restore_app_execution "$app_path"; then
        log 1 "Permisos restaurados para $app_name"
        # show_notification "Software Aprobado" "$app_name está listo para usar"
        apps_to_remove+=("$software_id")
      else
        show_dialog "Error de Restauración" "El software $app_name ha sido aprobado, pero hubo un problema al restaurar sus permisos." "stop"
      fi
    elif [ $verification_result -eq 2 ]; then
      # Software rechazado
      log 1 "$app_name ha sido rechazado. Eliminando..."
      
      # Usar la razón de la IA si está disponible y sanitizarla
      local rejection_reason="No cumple con las políticas de seguridad"
      if [ -n "$LAST_IA_DETAILED_REASON" ] && [ "$LAST_IA_DETAILED_REASON" != "null" ]; then
        rejection_reason=$(sanitize_ia_text "$LAST_IA_DETAILED_REASON")
        log 2 "Usando razón detallada de la IA sanitizada: $rejection_reason"
      elif [ -n "$LAST_IA_REASON" ] && [ "$LAST_IA_REASON" != "null" ]; then
        rejection_reason=$(sanitize_ia_text "$LAST_IA_REASON")
        log 2 "Usando razón de la IA sanitizada: $rejection_reason"
      fi
      
      # Verificar que el rejection_reason no esté vacío después de la sanitización
      if [ -z "$rejection_reason" ]; then
        rejection_reason="No cumple con las políticas de seguridad"
      fi
      
      local denial_message="El análisis de ciberseguridad de $app_name ha finalizado.\n\nRESULTADO: DENEGADO ❌\n\nRazón: $rejection_reason\n\nLa aplicación será eliminada del sistema por motivos de seguridad."
      
      show_dialog "Análisis Completado - DENEGADO" "$denial_message" "stop"
      
      if delete_application "$app_path"; then
        log 1 "Aplicación $app_name eliminada correctamente"
        # show_notification "Software Eliminado" "$app_name ha sido eliminado por seguridad"
        apps_to_remove+=("$software_id")
      else
        show_dialog "Error de Eliminación" "El software $app_name ha sido rechazado, pero hubo un problema al eliminarlo." "stop"
      fi
    else
      # Software aún pendiente
      log 2 "$app_name sigue pendiente de aprobación"
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
  
  log 2 "Intentando mostrar diálogo: $title"
  
  # Usar osascript con manejo de errores mejorado
  local dialog_result=$(osascript -e "display dialog \"$message\" buttons {\"OK\"} default button 1 with title \"$title\" with icon $icon" 2>&1)
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    log 2 "Diálogo mostrado exitosamente: $title"
    echo "$dialog_result"
  else
    log 1 "Error al mostrar diálogo: $dialog_result"
  fi
  
  return $exit_code
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
  
  # Verificar que la aplicación existe físicamente
  if [ ! -d "$app_path" ]; then
    log 1 "ADVERTENCIA: Aplicación no existe, omitiendo procesamiento: $app_path"
    return 0
  fi
  
  # Verificar que es realmente una aplicación macOS válida
  if [ ! -d "$app_path/Contents" ]; then
    log 1 "ADVERTENCIA: $app_path no parece ser una aplicación macOS válida, omitiendo"
    return 0
  fi
  
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
  
  # Pequeño delay para evitar problemas con diálogos consecutivos
  sleep 1
  
  # Mostrar diálogo de verificación de seguridad
  log 1 "Mostrando diálogo de verificación de seguridad para $app_name..."
  show_dialog "Proceso de Verificación de Seguridad" "El software $app_name no está registrado en nuestro sistema.\n\nSe iniciará un proceso completo de verificación que incluye:\n• Análisis de ciberseguridad\n• Evaluación de ciberriesgo\n• Validación de políticas empresariales\n\nEste proceso tardará entre 10 y 20 segundos.\nSe le notificará el resultado final una vez completada la verificación." "note"
  log 1 "Diálogo de verificación mostrado para $app_name"
  
  # Enviar aplicación al servidor para verificación
  log 1 "Enviando $app_name al servidor para verificación..."
  local verification_result
  verify_software "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature"
  verification_result=$?
  
  if [ $verification_result -eq 0 ]; then
    # Software aprobado
    log 1 "$app_name ha sido aprobado. Restaurando permisos de ejecución..."
    
    # Construir mensaje con razón de la IA si está disponible
    local approval_message="El análisis de ciberseguridad de $app_name ha finalizado.\n\nRESULTADO: APROBADO ✅\n\nLa aplicación ha superado todos los controles de seguridad y políticas empresariales."
    
    if [ -n "$LAST_IA_DETAILED_REASON" ] && [ "$LAST_IA_DETAILED_REASON" != "null" ]; then
      local ia_analysis=$(sanitize_ia_text "$LAST_IA_DETAILED_REASON")
      if [ -n "$ia_analysis" ]; then
        approval_message="$approval_message\n\nAnálisis de la IA: $ia_analysis"
      fi
    elif [ -n "$LAST_IA_REASON" ] && [ "$LAST_IA_REASON" != "null" ]; then
      local ia_evaluation=$(sanitize_ia_text "$LAST_IA_REASON")
      if [ -n "$ia_evaluation" ]; then
        approval_message="$approval_message\n\nEvaluación: $ia_evaluation"
      fi
    fi
    
    approval_message="$approval_message\n\nSe están restaurando los permisos de ejecución."
    
    show_dialog "Análisis Completado - APROBADO" "$approval_message" "note"
    
    if restore_app_execution "$app_path"; then
      log 1 "Permisos restaurados para $app_name"
      # show_notification "Software Aprobado" "$app_name está listo para usar"
      apps_to_remove+=("$software_id")
    else
      show_dialog "Error de Restauración" "El software $app_name ha sido aprobado, pero hubo un problema al restaurar sus permisos." "stop"
    fi
    elif [ $verification_result -eq 2 ]; then
    # Software rechazado
    log 1 "$app_name ha sido rechazado. Eliminando..."
    
    # Usar la razón de la IA si está disponible y sanitizarla
    local rejection_reason="No cumple con las políticas de seguridad"
    if [ -n "$LAST_IA_DETAILED_REASON" ] && [ "$LAST_IA_DETAILED_REASON" != "null" ]; then
      rejection_reason=$(sanitize_ia_text "$LAST_IA_DETAILED_REASON")
      log 2 "Usando razón detallada de la IA sanitizada: $rejection_reason"
    elif [ -n "$LAST_IA_REASON" ] && [ "$LAST_IA_REASON" != "null" ]; then
      rejection_reason=$(sanitize_ia_text "$LAST_IA_REASON")
      log 2 "Usando razón de la IA sanitizada: $rejection_reason"
    fi
    
    # Verificar que el rejection_reason no esté vacío después de la sanitización
    if [ -z "$rejection_reason" ]; then
      rejection_reason="No cumple con las políticas de seguridad"
    fi
    
    local denial_message="El análisis de ciberseguridad de $app_name ha finalizado.\n\nRESULTADO: DENEGADO ❌\n\nRazón: $rejection_reason\n\nLa aplicación será eliminada del sistema por motivos de seguridad."
    
    show_dialog "Análisis Completado - DENEGADO" "$denial_message" "stop"
    
      if delete_application "$app_path"; then
        log 1 "Aplicación $app_name eliminada correctamente"
        # show_notification "Software Eliminado" "$app_name ha sido eliminado por seguridad"
        apps_to_remove+=("$software_id")
      else
      show_dialog "Error de Eliminación" "El software $app_name ha sido rechazado, pero hubo un problema al eliminarlo." "stop"
      fi
    else
    # Software aún pendiente
    log 2 "$app_name sigue pendiente de aprobación"
  fi
}

# Verificar estado de autorización de un software específico
check_authorization_status() {
  local software_id="$1"
  local app_name="$2"
  local app_version="$3"
  local app_path="$4"
  local sha256="$5"
  local username="$6"
  local device_id="$7"
  local vendor="$8"
  local install_date="$9"
  local is_running="${10}"
  local digital_signature="${11}"
  
  log 2 "Consultando estado de autorización para $app_name (ID: $software_id)..."
  
  # Usar la función común para construir el JSON con todos los datos originales
  local json=$(build_software_json "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature" "$software_id")
  
  local status_response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    -d "$json" \
    "$VERIFICATION_ENDPOINT" 2>/dev/null)
  
  # DEBUG: Mostrar la respuesta completa para debugging
  log 2 "DEBUG - Respuesta del servidor para $app_name: $status_response"
  
  # Analizar respuesta para detectar estado actualizado
  if command -v jq &> /dev/null && echo "$status_response" | jq empty 2>/dev/null; then
    local is_approved=$(echo "$status_response" | jq -r '.isApproved // false')
    local is_rejected=$(echo "$status_response" | jq -r '.isRejected // false')
    local rejection_reason=$(echo "$status_response" | jq -r '.reason // ""')
    
    # Capturar razón detallada de la IA si está disponible
    local razon_de_la_IA=$(echo "$status_response" | jq -r '.razon_de_la_IA // ""')
    if [ -n "$razon_de_la_IA" ] && [ "$razon_de_la_IA" != "null" ]; then
      LAST_IA_DETAILED_REASON="$razon_de_la_IA"
      log 2 "Razón detallada de la IA capturada en check_authorization_status: '$razon_de_la_IA'"
      log 2 "Longitud de la razón de la IA: ${#razon_de_la_IA} caracteres"
    else
      log 2 "No se encontró razón detallada de la IA válida en check_authorization_status"
    fi
    
    log 2 "DEBUG - isApproved: $is_approved, isRejected: $is_rejected, reason: $rejection_reason"
    
    # Buscar indicadores de autorización en la respuesta
    if [[ "$status_response" == *"autorizado"* ]]; then
      local autorizado=$(echo "$status_response" | jq -r '.autorizado // null')
      local razon=$(echo "$status_response" | jq -r '.razon // ""')
      
      log 2 "DEBUG - autorizado: $autorizado, razon: $razon"
      
      if [ "$autorizado" = "0" ] || [ "$autorizado" = "false" ]; then
        log 2 "Autorización completada: RECHAZADO - $razon"
        # Usar razon_de_la_IA si está disponible, sino usar razon normal
        local final_reason="$razon"
        if [ -n "$razon_de_la_IA" ] && [ "$razon_de_la_IA" != "null" ]; then
          final_reason="$razon_de_la_IA"
        fi
        echo "rejected:$final_reason"
        return 0
      elif [ "$autorizado" = "1" ] || [ "$autorizado" = "true" ]; then
        log 2 "Autorización completada: APROBADO"
        # Usar razon_de_la_IA si está disponible, sino usar razon normal
        local final_reason="$razon"
        if [ -n "$razon_de_la_IA" ] && [ "$razon_de_la_IA" != "null" ]; then
          final_reason="$razon_de_la_IA"
        fi
        echo "approved:$final_reason"
        return 0
      fi
    fi
    
    # Verificar si el estado cambió en la base de datos
    if [ "$is_approved" = "true" ]; then
      log 2 "Software aprobado en base de datos"
      # Usar razon_de_la_IA si está disponible
      local final_reason="Software verificado correctamente"
      if [ -n "$razon_de_la_IA" ] && [ "$razon_de_la_IA" != "null" ]; then
        final_reason="$razon_de_la_IA"
      fi
      echo "approved:$final_reason"
      return 0
    elif [ "$is_rejected" = "true" ] || [ -n "$rejection_reason" ]; then
      log 2 "Software rechazado en base de datos: $rejection_reason"
      # Usar razon_de_la_IA si está disponible, sino usar rejection_reason
      local final_reason="$rejection_reason"
      if [ -n "$razon_de_la_IA" ] && [ "$razon_de_la_IA" != "null" ]; then
        final_reason="$razon_de_la_IA"
      fi
      echo "rejected:$final_reason"
      return 0
    fi
  else
    log 1 "Error al consultar estado de autorización: respuesta inválida"
    echo "error"
    return 1
  fi
  
  # Si llegamos aquí, el software sigue pendiente
  log 2 "Software sigue pendiente de autorización"
  echo "pending"
  return 1
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
    # Verificar si la respuesta es un JSON válido antes de procesarla
    if echo "$response" | jq empty 2>/dev/null; then
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
      log 1 "Error: Respuesta del servidor no es JSON válido: $response"
      return 2
    fi
  else
    log 1 "Error: jq no está instalado"
    return 2
  fi
}

# Limpiar lista de aplicaciones pendientes
clear_pending_apps_list() {
  log 1 "Limpiando lista de aplicaciones pendientes..."
  
  # Crear directorio de configuración si no existe
  mkdir -p "$(dirname "$PENDING_APPS_FILE")"
  
  # Crear archivo JSON vacío
  echo "[]" > "$PENDING_APPS_FILE"
  
  log 2 "Lista de aplicaciones pendientes limpiada"
}

# Función principal que ejecuta el ciclo de monitoreo
run_monitor() {
  log 1 "Iniciando monitor de instalaciones..."
  
  # Configurar carpetas necesarias
  setup_quarantine
  setup_config_dir
  
  # Limpiar lista de aplicaciones pendientes al iniciar
  clear_pending_apps_list
  
  # Cargar o crear configuración
  load_or_create_config
  
  # Verificar actualizaciones del agente
  check_for_updates
  
  # Variables para controlar el estado del monitor
  local monitoring_active=true
  local initial_apps=""
  
  # Mostrar notificación de inicio
  # show_notification "Monitor de Instalaciones" "Monitor de instalaciones iniciado"
  
  # Iniciar bucle principal que permanece activo incluso cuando el agente está inactivo
  while true; do
    # Comprobar estado actual del agente
    if [ "$AGENT_STATUS" = "inactive" ] && [ "$monitoring_active" = "true" ]; then
      log 1 "Agente configurado como inactivo. Entrando en modo espera"
      monitoring_active=false
      # show_notification "Monitor de Instalaciones" "Agente inactivo - modo espera activado"
    elif [ "$AGENT_STATUS" = "active" ] && [ "$monitoring_active" = "false" ]; then
      log 1 "Agente reactivado. Retomando monitorización"
      monitoring_active=true
      # show_notification "Monitor de Instalaciones" "Agente reactivado en modo $AGENT_MODE"
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
  
  # Escapar valores para JSON
  local escaped_device_id=$(escape_json_value "$device_id")
  local escaped_username=$(escape_json_value "$username")
  local escaped_status=$(escape_json_value "$AGENT_STATUS")
  
  # Construir payload con información del agente usando valores escapados
  local payload="{\"deviceId\":\"$escaped_device_id\",\"employeeEmail\":\"$escaped_username@example.com\",\"status\":\"$escaped_status\"}"
  
  # Debug: mostrar valores antes de enviar
  log 2 "DEBUG - device_id original: '$device_id'"
  log 2 "DEBUG - device_id escapado: '$escaped_device_id'"
  log 2 "DEBUG - username original: '$username'"
  log 2 "DEBUG - username escapado: '$escaped_username'"
  log 2 "DEBUG - status: '$AGENT_STATUS'"
  log 2 "DEBUG - payload JSON: '$payload'"
  
  # Verificar que el JSON es válido antes de enviarlo
  if command -v jq &> /dev/null; then
    if ! echo "$payload" | jq empty 2>/dev/null; then
      log 1 "ERROR: JSON del ping es inválido: $payload"
      return 1
    fi
  fi
  
  # Enviar ping al servidor
  local ping_response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    -d "$payload" \
    "$PING_ENDPOINT")
  
  # Debug: mostrar respuesta del servidor
  log 2 "DEBUG - ping response: '$ping_response'"
  
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
    log 1 "Error al enviar ping al servidor: $ping_response"
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