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
API_KEY="387a3cb4b8ff8085870824263cf07cf8"  # Debe coincidir con el valor en la base de datos
# TEAM_NAME se resuelve automáticamente en el servidor usando la API key
APPS_DIRECTORY="/Applications"
SCAN_INTERVAL=1  # segundos entre escaneos - verificar aplicaciones pendientes cada 10 segundos
QUARANTINE_DIR="$HOME/Library/Application Support/AppQuarantine"

# Endpoints globales - el servidor resolverá el team automáticamente usando la API key
VERIFICATION_ENDPOINT="$BACKEND_URL/validate_software"
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
  log 1 " Team       : Resuelto automáticamente por API key"
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

# Verificar si un team existe en el servidor
verify_team_exists() {
  local team_to_verify="$1"
  
  log 2 "Verificando si el team '$team_to_verify' existe..."
  
  # Intentar acceder a los settings del team
  local verify_response=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    --connect-timeout 15 \
    "$BACKEND_URL/teams/$team_to_verify/settings")
  
  # Si no es HTML, el team probablemente existe
  if [[ "$verify_response" != *"DOCTYPE html"* ]] && [[ "$verify_response" != *"<html"* ]] && [[ "$verify_response" != *"404"* ]]; then
    log 2 "Team '$team_to_verify' verificado exitosamente"
    return 0
  else
    log 1 "Team '$team_to_verify' no existe o no es accesible"
    return 1
  fi
}

# Actualizar endpoints dinámicamente basado en el team
update_endpoints() {
  VERIFICATION_ENDPOINT="$BACKEND_URL/teams/$TEAM_NAME/validate_software"
  SETTINGS_ENDPOINT="$BACKEND_URL/teams/$TEAM_NAME/settings"
  STATUS_ENDPOINT="$BACKEND_URL/teams/$TEAM_NAME/agents/status"
  PING_ENDPOINT="$BACKEND_URL/teams/$TEAM_NAME/agents/ping"
  SOFTWARE_STATUS_ENDPOINT="$BACKEND_URL/teams/$TEAM_NAME/software/status"
  
  log 2 "Endpoints actualizados para el equipo: $TEAM_NAME"
  
  # Verificar que el team realmente existe
  if ! verify_team_exists "$TEAM_NAME"; then
    log 1 "ADVERTENCIA: El team '$TEAM_NAME' podría no existir en el servidor"
    log 1 "Use '$0 --list-teams' para ver teams disponibles"
  fi
}

# Verificar autenticación y diagnosticar problemas
diagnose_authentication() {
  log 1 "=========================================="
  log 1 "DIAGNÓSTICO DE AUTENTICACIÓN"
  log 1 "=========================================="
  
  log 1 "API Key configurada: ${API_KEY:0:8}..."
  log 1 "Team: Resuelto automáticamente por API key"
  log 1 "Backend URL: $BACKEND_URL"
  
  # Probar endpoint básico sin autenticación
  local health_response=$(curl -s --connect-timeout 10 "$BACKEND_URL/health" 2>/dev/null || echo "CONNECTION_FAILED")
  
  if [ "$health_response" = "CONNECTION_FAILED" ]; then
    log 1 "❌ ERROR: No se puede conectar al servidor backend"
    log 1 "Verifique que el servidor esté ejecutándose en $BACKEND_URL"
  else
    log 1 "✅ Conexión al servidor: OK"
  fi
  
  # Probar autenticación con diferentes métodos
  log 1 "Probando autenticación por API key..."
  
  local auth_test_response=$(curl -s -X GET \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    --connect-timeout 10 \
    "$BACKEND_URL/agents/ping" 2>/dev/null)
  
  if [[ "$auth_test_response" == *"/auth/login"* ]]; then
    log 1 "❌ Los endpoints están protegidos por NextAuth (autenticación web)"
    log 1 "SOLUCIÓN: Crear endpoints específicos para agentes que soporten API keys"
    log 1 ""
    log 1 "Endpoints necesarios en el SaaS:"
    log 1 "  • /api/agents/ping (sin NextAuth, solo API key)"
    log 1 "  • /api/agents/validate-software (sin NextAuth, solo API key)"
    log 1 "  • /api/agents/settings (sin NextAuth, solo API key)"
    log 1 "  • /api/agents/detect-team (sin NextAuth, solo API key)"
  elif [[ "$auth_test_response" == *"["* ]] || [[ "$auth_test_response" == *"{"* ]]; then
    log 1 "✅ Autenticación por API key: OK"
  else
    log 1 "❓ Respuesta inesperada del servidor: $auth_test_response"
  fi
  
  log 1 "=========================================="
}

# Generar código de solución para el backend
generate_backend_solution() {
  local team_name="$1"
  
  log 1 "=========================================="
  log 1 "CÓDIGO DE SOLUCIÓN PARA EL BACKEND"
  log 1 "=========================================="
  log 1 ""
  log 1 "Archivo: pages/api/agents/ping.ts"
  log 1 "Problema: El modelo Employee requiere campo 'team' obligatorio"
  log 1 ""
  log 1 "SOLUCIÓN (reemplazar la sección de creación de empleado):"
  log 1 ""
  
  cat << 'EOF'
// Extraer teamName del payload
const { teamName = 'default', deviceId, employeeEmail, status } = req.body;

// Buscar empleado existente
let employee = await prisma.employee.findUnique({
  where: { deviceId },
  include: { team: true }
});

if (!employee) {
  // Buscar o crear el team
  let team = await prisma.team.findUnique({
    where: { slug: teamName }
  });

  if (!team) {
    log.info(`Creando nuevo team: ${teamName}`);
    team = await prisma.team.create({
      data: { 
        name: teamName.charAt(0).toUpperCase() + teamName.slice(1),
        slug: teamName 
      }
    });
  }

  // Crear empleado con relación al team
  const genericEmail = `device_${deviceId}@unknown.com`;
  
  employee = await prisma.employee.create({
    data: {
      name: `Device ${deviceId}`,
      email: genericEmail,
      department: 'Unassigned',
      role: 'MEMBER',
      status: 'active',
      deviceId: deviceId,
      isActive: true,
      lastPing: new Date(),
      team: { connect: { id: team.id } }  // ← SOLUCIÓN: Conectar al team
    },
    include: { team: true }
  });
  
  log.info(`Empleado creado automáticamente: ${employee.email} en team: ${team.name}`);
} else {
  // Actualizar lastPing del empleado existente
  employee = await prisma.employee.update({
    where: { id: employee.id },
    data: { lastPing: new Date(), isActive: true },
    include: { team: true }
  });
}
EOF

  log 1 ""
  log 1 "=========================================="
  log 1 "ARCHIVO COMPLETO CORREGIDO:"
  log 1 "https://gist.github.com/example/backend-ping-solution"
  log 1 "=========================================="
}

# Verificar y cargar configuración guardada o crearla si no existe
load_or_create_config() {
  local device_id=$(get_device_id)
  local username=$(get_username)
  
  # Inicializar variable para la última sincronización exitosa
  LAST_SYNC_TIME=0
  
  # Intentar detectar el team automáticamente desde el servidor primero
  # No fallar si no se puede detectar, solo usarlo si está disponible
  if ! detect_team_from_server; then
    log 2 "No se pudo detectar team automáticamente. Intentando con lista de teams..."
    
    # Intentar obtener lista de teams disponibles como fallback
    local teams_response=$(curl -s -X GET \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -H "Accept: application/json" \
      -H "User-Agent: SoftCheck-Agent/1.0" \
      --connect-timeout 30 \
      "$BACKEND_URL/teams")
    
    if command -v jq &> /dev/null && echo "$teams_response" | jq empty 2>/dev/null; then
      local first_team=$(echo "$teams_response" | jq -r '.[0].slug // .[0].name // ""' 2>/dev/null)
      if [ -n "$first_team" ] && [ "$first_team" != "null" ] && [ "$first_team" != "default" ]; then
        log 1 "Usando el primer team disponible como fallback: $first_team"
        TEAM_NAME="$first_team"
        update_endpoints
      else
        log 1 "ADVERTENCIA: No hay teams válidos disponibles. El agente podría no funcionar correctamente con team: $TEAM_NAME"
      fi
    else
      log 1 "ADVERTENCIA: No se pudo obtener lista de teams. Continuando con team: $TEAM_NAME"
    fi
  fi
  
  if [ -f "$AGENT_CONFIG_FILE" ]; then
    # Verificar si el archivo de configuración es válido
    if jq -e . "$AGENT_CONFIG_FILE" >/dev/null 2>&1; then
      # Cargar configuración desde el archivo
      AGENT_STATUS=$(jq -r '.status // "active"' "$AGENT_CONFIG_FILE")
      AGENT_MODE=$(jq -r '.mode // "active"' "$AGENT_CONFIG_FILE")
      AGENT_AUTO_UPDATE=$(jq -r '.autoUpdate // true' "$AGENT_CONFIG_FILE")
      
      # Cargar team name si está disponible en la configuración
      local saved_team=$(jq -r '.teamName // "default"' "$AGENT_CONFIG_FILE")
      if [ -n "$saved_team" ] && [ "$saved_team" != "null" ]; then
        TEAM_NAME="$saved_team"
        log 2 "Team cargado desde configuración: $TEAM_NAME"
        update_endpoints
      fi
      
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
  log 2 "Intentando endpoint: $SETTINGS_ENDPOINT"
  
  # Obtener configuración desde el servidor con cabeceras mejoradas
  local response=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Authorization: Bearer $API_KEY" \
    -H "X-Auth-Token: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    -H "Cache-Control: no-cache" \
    --connect-timeout 30 \
    "$SETTINGS_ENDPOINT")
  
  # Detectar errores HTTP comunes y redirecciones de login
  if [[ "$response" == *"DOCTYPE html"* ]] || [[ "$response" == *"/auth/login"* ]] || [[ "$response" == *"callbackUrl="* ]] || [[ "$response" == *"<html"* ]] || [[ "$response" == *"404"* ]] || [[ "$response" == *"Not Found"* ]]; then
    if [[ "$response" == *"/auth/login"* ]]; then
      log 1 "ERROR: Endpoint requiere autenticación web. Intentando endpoint global con API key..."
    else
      log 1 "ERROR: Endpoint del team no válido o no existe. Intentando endpoint global..."
    fi
    
    # Intentar con endpoint global (sin team)
    local global_endpoint="$BACKEND_URL/settings"
    log 2 "Intentando endpoint global: $global_endpoint"
    
    response=$(curl -s -X GET \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -H "Authorization: Bearer $API_KEY" \
      -H "X-Auth-Token: $API_KEY" \
      -H "Accept: application/json" \
      -H "User-Agent: SoftCheck-Agent/1.0" \
      -H "Cache-Control: no-cache" \
      --connect-timeout 30 \
      "$global_endpoint")
    
    # Verificar si el endpoint global funciona
    if [[ "$response" == *"DOCTYPE html"* ]] || [[ "$response" == *"/auth/login"* ]] || [[ "$response" == *"callbackUrl="* ]] || [[ "$response" == *"<html"* ]]; then
      if [[ "$response" == *"/auth/login"* ]]; then
        log 1 "ERROR: También el endpoint global requiere autenticación web."
        log 1 "PROBLEMA CRÍTICO: Los endpoints no están configurados para API keys."
        log 1 "El SaaS necesita endpoints que soporten autenticación por API key para agentes."
      else
        log 1 "ERROR: También falló el endpoint global. Posible problema de servidor."
      fi
    return 1
    fi
    
    # Si el endpoint global funciona, intentar detectar el team correcto
    if [[ "$response" == *"\"isActive\""* ]]; then
      log 1 "Endpoint global funcionó. Intentando redetectar el team correcto..."
      if detect_team_from_server; then
        log 1 "Team redetectado exitosamente. Reintentando sincronización..."
        return $(sync_config_with_server)
      else
        log 1 "No se pudo detectar team válido. Continuando con configuración global..."
        # Continuar procesando con la respuesta del endpoint global
      fi
    fi
  fi
  
  # Verificar si obtuvo respuesta válida JSON con isActive
  if [[ "$response" == *"\"isActive\""* ]]; then
    # Extraer valores del JSON (requiere jq instalado)
    if command -v jq &> /dev/null; then
      local isActive=$(echo "$response" | jq -r '.isActive')
      local isActiveMode=$(echo "$response" | jq -r '.isActiveMode')
      local autoUpdate=$(echo "$response" | jq -r '.autoUpdate')
        local shouldDelete=$(echo "$response" | jq -r '.shouldDelete')
        
        # Verificar si el agente debe eliminarse
        if [ "$shouldDelete" = "true" ]; then
          log 1 "ELIMINACIÓN SOLICITADA: El servidor ha marcado este agente para eliminación"
          perform_self_deletion
          return 0
        fi
      
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

# Función para detectar automáticamente el team del dispositivo
detect_team_from_server() {
  local device_id=$(get_device_id)
  local username=$(get_username)
  
  log 2 "Detectando equipo desde el servidor..."
  
  # Endpoint para detectar el team del dispositivo
  local detect_endpoint="$BACKEND_URL/agents/detect-team"
  log 2 "Endpoint de detección: $detect_endpoint"
  
  # Construir payload para detectar el team
  local payload="{\"deviceId\":\"$(escape_json_value "$device_id")\",\"username\":\"$(escape_json_value "$username")\"}"
  
  # Realizar solicitud al servidor
  local response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    --connect-timeout 30 \
    -d "$payload" \
    "$detect_endpoint")
  
  log 2 "Respuesta de detección de team: $response"
  
  # Verificar si es HTML (error 404 o similar)
  if [[ "$response" == *"DOCTYPE html"* ]] || [[ "$response" == *"<html"* ]] || [[ "$response" == *"404"* ]]; then
    log 1 "El endpoint de detección de team no existe. Intentando método alternativo..."
    
    # Método alternativo: intentar obtener lista de teams disponibles
    local teams_endpoint="$BACKEND_URL/teams"
    log 2 "Intentando obtener lista de teams: $teams_endpoint"
    
    local teams_response=$(curl -s -X GET \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -H "Accept: application/json" \
      -H "User-Agent: SoftCheck-Agent/1.0" \
      --connect-timeout 30 \
      "$teams_endpoint")
    
    if command -v jq &> /dev/null && echo "$teams_response" | jq empty 2>/dev/null; then
      local first_team=$(echo "$teams_response" | jq -r '.[0].slug // .[0].name // ""' 2>/dev/null)
      if [ -n "$first_team" ] && [ "$first_team" != "null" ]; then
        log 1 "Usando el primer team disponible: $first_team"
        TEAM_NAME="$first_team"
        update_endpoints
        return 0
      fi
    fi
    
    log 1 "No se encontraron teams válidos. Manteniendo team actual: $TEAM_NAME"
    return 1
  fi
  
  # Analizar respuesta para obtener el team
  if command -v jq &> /dev/null && echo "$response" | jq empty 2>/dev/null; then
    local detected_team=$(echo "$response" | jq -r '.teamName // .team // ""')
    local success=$(echo "$response" | jq -r '.success // false')
    
    if [ "$success" = "true" ] && [ -n "$detected_team" ] && [ "$detected_team" != "null" ]; then
      log 1 "Equipo detectado desde el servidor: $detected_team"
      TEAM_NAME="$detected_team"
      update_endpoints
      return 0
    else
      log 1 "Respuesta del servidor no contiene team válido"
      return 1
    fi
  else
    log 1 "Respuesta del servidor no es JSON válido"
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
    \"teamName\": \"$TEAM_NAME\",
    \"lastSync\": \"$timestamp\"
  }"
  
  # Guardar al archivo de configuración
  echo "$config" > "$AGENT_CONFIG_FILE"
  
  # También guardar a un archivo de respaldo
  echo "$config" > "${AGENT_CONFIG_FILE}.backup"
  
  log 2 "Archivo de configuración actualizado (Team: $TEAM_NAME)"
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
  
  # Crear objeto JSON base con todos los datos escapados - el servidor resolverá el team automáticamente
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
  
  # Verificar si recibimos HTML (endpoint no existe)
  if [[ "$response" == *"DOCTYPE html"* ]] || [[ "$response" == *"<html"* ]] || [[ "$response" == *"404"* ]]; then
    log 1 "DEBUG - Endpoint del team no existe. Intentando endpoint global..."
    
    # Intentar con endpoint global
    local global_verification_endpoint="$BACKEND_URL/validate_software"
    log 1 "DEBUG - Intentando endpoint global: $global_verification_endpoint"
    
    curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -H "Accept: application/json" \
      -H "User-Agent: SoftCheck-Agent/1.0" \
      -d "$json" \
      "$global_verification_endpoint" \
      2> "$temp_headers_file" \
      > "$temp_response_file"
    
    curl_exit_code=$?
    response=$(cat "$temp_response_file")
    curl_error=$(cat "$temp_headers_file")
    
    log 1 "DEBUG - Respuesta del endpoint global: $response"
  fi
  
  # DEBUG: Mostrar respuesta del servidor
  log 1 "DEBUG - curl exit code: $curl_exit_code"
  log 1 "DEBUG - curl error: $curl_error"
  log 1 "DEBUG - Respuesta del servidor: $response"
  
  # Detectar redirección de login (problema de autenticación)
  if [[ "$response" == *"/auth/login"* ]] || [[ "$response" == *"callbackUrl="* ]]; then
    log 1 "ERROR: Recibida redirección de login. El endpoint requiere autenticación web en lugar de API key."
    log 1 "Esto indica que el endpoint no está configurado para aceptar API keys."
    log 1 "Verificar:"
    log 1 "  1. Que el endpoint soporte autenticación por API key"
    log 1 "  2. Que la API_KEY sea válida: ${API_KEY:0:8}..."
    log 1 "  3. Que el middleware de autenticación esté configurado correctamente"
    
    # Intentar con headers adicionales de autenticación
    log 1 "Intentando con headers de autenticación adicionales..."
    
    curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -H "Authorization: Bearer $API_KEY" \
      -H "X-Auth-Token: $API_KEY" \
      -H "Accept: application/json" \
      -H "User-Agent: SoftCheck-Agent/1.0" \
      -H "Cache-Control: no-cache" \
      -d "$json" \
      "$VERIFICATION_ENDPOINT" \
      2> "$temp_headers_file" \
      > "$temp_response_file"
    
    curl_exit_code=$?
    response=$(cat "$temp_response_file")
    curl_error=$(cat "$temp_headers_file")
    
    log 1 "DEBUG - Respuesta con headers adicionales: $response"
    
    # Si aún recibimos redirección, el endpoint no soporta API keys
    if [[ "$response" == *"/auth/login"* ]]; then
      log 1 "ERROR CRÍTICO: El endpoint no soporta autenticación por API key."
      log 1 "Necesita configurar endpoints específicos para API en el SaaS."
      return 1
    fi
  fi
  
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

# FUNCIÓN COMENTADA: Enviar inventario inicial de software al servidor
# Esta función ha sido deshabilitada para que el agente solo procese nuevos softwares
# instalados después de su primera ejecución, no los preexistentes en el sistema
#
# send_initial_software_inventory() {
#   log 1 "======================================"
#   log 1 "ENVIANDO INVENTARIO INICIAL DE SOFTWARE"
#   log 1 "======================================"
#   
#   # Obtener lista de todas las aplicaciones instaladas
#   local all_apps=$(get_current_apps)
#   local app_count=$(echo "$all_apps" | wc -l | tr -d ' ')
#   
#   log 1 "Se encontraron $app_count aplicaciones instaladas"
#   
#   if [ "$app_count" -eq 0 ]; then
#     log 1 "No se encontraron aplicaciones para enviar"
#     return 0
#   fi
#   
#   # Obtener información común del dispositivo
#   local username=$(get_username)
#   local device_id=$(get_device_id)
#   
#   local success_count=0
#   local error_count=0
#   
#   # Procesar cada aplicación encontrada
#   while IFS= read -r app; do
#     if [ -n "$app" ]; then
#       local app_name="${app%.app}"
#       local app_path="$APPS_DIRECTORY/$app"
#       
#       # Verificar que la aplicación existe y es válida
#       if [ -d "$app_path" ] && [ -d "$app_path/Contents" ]; then
#         log 1 "Procesando aplicación inicial: $app_name"
#         
#         # Recopilar información completa de la aplicación
#         local app_version=$(get_app_version "$app_path")
#         local vendor=$(get_app_vendor "$app_path")
#         local install_date=$(get_install_date "$app_path")
#         local is_running=$(is_app_running "$app_name")
#         local digital_signature=$(check_digital_signature "$app_path")
#         local sha256="no_disponible"
#         
#         # Calcular SHA256 del ejecutable principal si es posible
#         local main_executable=$(find_main_executable "$app_path")
#         if [ -n "$main_executable" ]; then
#           sha256=$(calculate_sha256 "$main_executable")
#         fi
#         
#         log 2 "Enviando datos de $app_name al servidor..."
#         log 2 "  - Versión: $app_version"
#         log 2 "  - Vendor: $vendor"
#         log 2 "  - Fecha instalación: $install_date"
#         log 2 "  - SHA256: ${sha256:0:16}..."
#         
#         # Enviar aplicación al servidor usando la función de verificación existente
#         if verify_software "$app_name" "$app_version" "$app_path" "$sha256" "$username" "$device_id" "$vendor" "$install_date" "$is_running" "$digital_signature"; then
#           log 2 "✓ $app_name enviado exitosamente"
#           success_count=$((success_count + 1))
#         else
#           log 1 "✗ Error al enviar $app_name"
#           error_count=$((error_count + 1))
#         fi
#         
#         # Pequeño delay para no sobrecargar el servidor
#         sleep 0.5
#       else
#         log 1 "ADVERTENCIA: $app_path no es una aplicación macOS válida"
#         error_count=$((error_count + 1))
#       fi
#     fi
#   done < <(echo "$all_apps")
#   
#   log 1 "======================================"
#   log 1 "INVENTARIO INICIAL COMPLETADO"
#   log 1 "======================================"
#   log 1 "Aplicaciones enviadas exitosamente: $success_count"
#   log 1 "Errores encontrados: $error_count"
#   log 1 "Total procesadas: $((success_count + error_count))"
#   log 1 "======================================"
#   
#   # Mostrar notificación de finalización
#   if [ $error_count -eq 0 ]; then
#     log 1 "Todos los softwares fueron registrados exitosamente en el servidor"
#   else
#     log 1 "Se completó el inventario con algunos errores. Revisar logs para detalles."
#   fi
#   
#   return 0
# }

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
  
  # COMENTADO: Enviar inventario inicial de software
  # Esta funcionalidad ha sido deshabilitada para que el agente solo bloquee
  # nuevos softwares instalados después de su primera ejecución, no los preexistentes
  # if [ "$AGENT_STATUS" = "active" ]; then
  #   send_initial_software_inventory
  # else
  #   log 1 "Agente inactivo - omitiendo inventario inicial"
  # fi
  
  log 1 "Inventario inicial omitido - solo se procesarán nuevas instalaciones"
  
  # Variables para controlar el estado del monitor
  local monitoring_active=true
  local last_scan_apps=""
  
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
      # Reinicializar la lista de aplicaciones para detectar cambios durante inactividad
      last_scan_apps=""
    fi
    
    # Si el agente está activo, realizar el monitoreo normal
    if [ "$monitoring_active" = "true" ]; then
      # Verificar aplicaciones pendientes
      check_pending_applications
      
      # Obtener lista actual de aplicaciones
      local current_apps=$(get_current_apps)
      
      # En el primer escaneo, solo inicializar la lista sin procesar
      if [ -z "$last_scan_apps" ]; then
        last_scan_apps="$current_apps"
        log 1 "Se han detectado $(echo "$current_apps" | wc -l | tr -d ' ') aplicaciones en el primer escaneo"
      else
        # Buscar aplicaciones que NO estaban en el escaneo anterior
        # Esto detecta nuevas instalaciones (incluyendo reinstalaciones)
        while IFS= read -r app; do
          if [ -n "$app" ] && ! app_exists "$app" "$last_scan_apps"; then
            log 1 "Nueva instalación detectada: $app"
            
            # Extraer nombre sin extensión .app
            local app_name="${app%.app}"
            
            # SIEMPRE procesar la aplicación - cada instalación pasa por verificación
            process_new_application "$app_name" "$APPS_DIRECTORY/$app"
          fi
        done < <(echo "$current_apps")
        
        # Actualizar lista del último escaneo
        last_scan_apps="$current_apps"
      fi
      
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
  log 2 "Endpoint de ping: $PING_ENDPOINT"
  
  # Escapar valores para JSON
  local escaped_device_id=$(escape_json_value "$device_id")
  local escaped_username=$(escape_json_value "$username")
  local escaped_status=$(escape_json_value "$AGENT_STATUS")
  # Construir payload simplificado - el servidor resolverá el team automáticamente usando la API key
  local payload="{
    \"deviceId\":\"$escaped_device_id\",
    \"employeeEmail\":\"$escaped_username@example.com\",
    \"status\":\"$escaped_status\"
  }"
  
  # Debug: mostrar valores antes de enviar
  log 2 "DEBUG - device_id: '$device_id'"
  log 2 "DEBUG - username: '$username'"
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
    -H "Authorization: Bearer $API_KEY" \
    -H "X-Auth-Token: $API_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: SoftCheck-Agent/1.0" \
    -H "Cache-Control: no-cache" \
    -d "$payload" \
    "$PING_ENDPOINT")
  
  # Debug: mostrar respuesta del servidor
  log 2 "DEBUG - ping response: '$ping_response'"
  
  # Verificar si recibimos HTML (endpoint no existe) o redirección de login
  if [[ "$ping_response" == *"DOCTYPE html"* ]] || [[ "$ping_response" == *"<html"* ]] || [[ "$ping_response" == *"404"* ]] || [[ "$ping_response" == *"Not Found"* ]] || [[ "$ping_response" == *"/auth/login"* ]] || [[ "$ping_response" == *"callbackUrl="* ]]; then
    if [[ "$ping_response" == *"/auth/login"* ]]; then
      log 1 "FALLO: Endpoint de ping requiere autenticación web en lugar de API key"
    else
      log 1 "FALLO: Endpoint de ping del team '$TEAM_NAME' no existe o devolvió 404"
    fi
    log 1 "Respuesta recibida: $ping_response"
    
    # Si el team es "default", significa que no hemos detectado un team válido
    if [ "$TEAM_NAME" = "default" ]; then
      log 1 "ERROR CRÍTICO: Team 'default' no es válido en el SaaS. Necesita configurar un team real."
      log 1 "Use: $0 --team NOMBRE_DEL_TEAM_REAL"
      log 1 "O configure el endpoint /api/agents/detect-team en el servidor"
      return 1
    fi
    
    # Si tenemos un team específico pero falló, intentar redetectar
    log 1 "Intentando redetectar team válido..."
    if detect_team_from_server; then
      log 1 "Team redetectado: $TEAM_NAME. Reintentando ping..."
      return $(ping_server)  # Recursiva para reintentar con el nuevo team
    fi
    
    # Como último recurso, intentar con endpoint global (aunque probablemente no exista)
    local global_ping_endpoint="$BACKEND_URL/agents/ping"
    log 1 "ÚLTIMO RECURSO: Intentando endpoint global: $global_ping_endpoint"
    
    ping_response=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -H "Authorization: Bearer $API_KEY" \
      -H "X-Auth-Token: $API_KEY" \
      -H "Accept: application/json" \
      -H "User-Agent: SoftCheck-Agent/1.0" \
      -H "Cache-Control: no-cache" \
      -d "$payload" \
      "$global_ping_endpoint")
    
    log 2 "DEBUG - ping global response: '$ping_response'"
    
    # Si el global también falla, es un error crítico
    if [[ "$ping_response" == *"DOCTYPE html"* ]] || [[ "$ping_response" == *"404"* ]] || [[ "$ping_response" == *"/auth/login"* ]]; then
      if [[ "$ping_response" == *"/auth/login"* ]]; then
        log 1 "ERROR CRÍTICO: Los endpoints requieren autenticación web (NextAuth.js)."
        log 1 "SOLUCIÓN NECESARIA: Crear endpoints específicos para API keys en el SaaS."
        log 1 "Ejemplo: /api/agents/ping (sin protección NextAuth, solo API key)"
      else
        log 1 "ERROR CRÍTICO: Ni los endpoints del team ni el global funcionan."
      fi
      log 1 "Verifique:"
      log 1 "  1. Que el team '$TEAM_NAME' existe en el SaaS"
      log 1 "  2. Que los endpoints están configurados para API keys"
      log 1 "  3. Que la API_KEY es válida: ${API_KEY:0:8}..."
      log 1 "  4. Que no hay middleware NextAuth protegiendo los endpoints de API"
      return 1
    fi
  fi
  
  # Detectar error específico de Prisma por team faltante
  if [[ "$ping_response" == *"Argument \`team\` is missing"* ]] || [[ "$ping_response" == *"PrismaClientValidationError"* ]] || [[ "$ping_response" == *"TeamCreateWithoutEmployeesInput"* ]]; then
    log 1 "ERROR CRÍTICO: El modelo Employee en el SaaS requiere un campo 'team' obligatorio"
    log 1 "Respuesta del servidor: $ping_response"
    log 1 ""
    log 1 "SOLUCIÓN EN EL BACKEND (pages/api/agents/ping.ts):"
    log 1 "El código necesita encontrar o crear el team antes de crear el empleado:"
    log 1 ""
    log 1 "// Buscar o crear el team"
    log 1 "let team = await prisma.team.findUnique({"
    log 1 "  where: { slug: teamName }"
    log 1 "});"
    log 1 ""
    log 1 "if (!team) {"
    log 1 "  team = await prisma.team.create({"
    log 1 "    data: { name: teamName, slug: teamName }"
    log 1 "  });"
    log 1 "}"
    log 1 ""
    log 1 "// Crear empleado con relación al team"
    log 1 "employee = await prisma.employee.create({"
    log 1 "  data: {"
    log 1 "    name: \`Device \${deviceId}\`,"
    log 1 "    email: genericEmail,"
    log 1 "    department: 'Unassigned',"
    log 1 "    role: 'MEMBER',"
    log 1 "    status: 'active',"
    log 1 "    deviceId: deviceId,"
    log 1 "    isActive: true,"
    log 1 "    lastPing: new Date(),"
    log 1 "    team: { connect: { id: team.id } }  // ← Conexión correcta"
    log 1 "  }"
    log 1 "});"
    log 1 ""
    return 1
  fi
  
  # Verificar si la respuesta fue exitosa
  if [[ "$ping_response" == *"\"success\":true"* ]] || [[ "$ping_response" == *"\"status\":\"ok\""* ]]; then
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

# Función para realizar la auto-eliminación del agente
perform_self_deletion() {
  log 1 "=========================================="
  log 1 "INICIANDO PROCESO DE AUTO-ELIMINACIÓN"
  log 1 "=========================================="
  
  # Mostrar notificación al usuario
  osascript -e 'display notification "El agente SoftCheck se está eliminando del sistema según las instrucciones del servidor." with title "SoftCheck Agent" sound name "Glass"' 2>/dev/null
  
  # Detener cualquier proceso relacionado
  log 1 "Deteniendo procesos relacionados..."
  
  # Matar el daemon de sincronización si existe
  if [ -n "$SYNC_DAEMON_PID" ]; then
    kill $SYNC_DAEMON_PID 2>/dev/null
    log 1 "Daemon de sincronización detenido (PID: $SYNC_DAEMON_PID)"
  fi
  
  # Buscar y matar otros procesos del agente
  pkill -f "MacOSInstallAgent" 2>/dev/null
  
  # Eliminar archivos de configuración
  log 1 "Eliminando archivos de configuración..."
  rm -rf "$HOME/.softcheck" 2>/dev/null
  
  # Eliminar directorio de cuarentena
  log 1 "Eliminando directorio de cuarentena..."
  rm -rf "$QUARANTINE_DIR" 2>/dev/null
  
  # Eliminar archivos de log si existen
  log 1 "Eliminando archivos de log..."
  rm -f "$HOME/Library/Logs/SoftCheck"* 2>/dev/null
  rm -f "/tmp/softcheck"* 2>/dev/null
  
  # Buscar y eliminar LaunchAgents/LaunchDaemons relacionados
  log 1 "Eliminando LaunchAgents y LaunchDaemons..."
  rm -f "$HOME/Library/LaunchAgents/com.softcheck."* 2>/dev/null
  rm -f "/Library/LaunchAgents/com.softcheck."* 2>/dev/null
  rm -f "/Library/LaunchDaemons/com.softcheck."* 2>/dev/null
  
  # Descargar LaunchAgents si están cargados
  launchctl unload "$HOME/Library/LaunchAgents/com.softcheck."* 2>/dev/null
  
  # Eliminar preferencias del sistema
  log 1 "Eliminando preferencias del sistema..."
  defaults delete com.softcheck.agent 2>/dev/null
  
  # Limpiar cache de aplicaciones
  log 1 "Limpiando cache..."
  rm -rf "$HOME/Library/Caches/com.softcheck."* 2>/dev/null
  
  # Eliminar entradas del Keychain si existen
  log 1 "Eliminando entradas del Keychain..."
  security delete-generic-password -s "SoftCheck Agent" 2>/dev/null
  
  # Restaurar permisos de aplicaciones que puedan estar restringidas
  log 1 "Restaurando permisos de aplicaciones restringidas..."
  find "/Applications" -name ".softcheck" -type d 2>/dev/null | while read -r metadata_dir; do
    local app_path=$(dirname "$(dirname "$metadata_dir")")
    log 1 "Restaurando permisos para: $app_path"
    restore_app_execution "$app_path"
  done
  
  # Crear script de auto-eliminación que se ejecutará después de que este proceso termine
  local self_delete_script="/tmp/softcheck_self_delete_$(date +%s).sh"
  
  cat > "$self_delete_script" << 'EOF'
#!/bin/bash
# Script de auto-eliminación de SoftCheck Agent
# Este script se ejecuta después de que el agente principal termine

sleep 3

# Obtener el directorio donde está ubicado el agente
AGENT_SCRIPT="$1"
AGENT_DIR=$(dirname "$AGENT_SCRIPT")

echo "Eliminando agente desde: $AGENT_SCRIPT"
echo "Directorio del agente: $AGENT_DIR"

# Eliminar el script del agente
rm -f "$AGENT_SCRIPT" 2>/dev/null

# Si el agente está en un directorio específico, eliminar todo el directorio
if [[ "$AGENT_DIR" == *"SoftCheck"* ]] || [[ "$AGENT_DIR" == *"softcheck"* ]]; then
  echo "Eliminando directorio completo: $AGENT_DIR"
  rm -rf "$AGENT_DIR" 2>/dev/null
fi

# Eliminar archivos de backup
rm -f "${AGENT_SCRIPT}_backup"* 2>/dev/null
rm -f "${AGENT_SCRIPT}.backup"* 2>/dev/null

# Eliminar logs adicionales
rm -f "$AGENT_DIR"/*.log 2>/dev/null
rm -f "$AGENT_DIR"/agent*.log 2>/dev/null

# Mostrar notificación final
osascript -e 'display notification "SoftCheck Agent ha sido eliminado completamente del sistema." with title "SoftCheck Agent" sound name "Glass"' 2>/dev/null

# Auto-eliminar este script
rm -f "$0"

echo "Auto-eliminación completada."
EOF

  chmod +x "$self_delete_script"
  
  # Enviar notificación final al servidor
  log 1 "Enviando notificación final al servidor..."
  local device_id=$(get_device_id)
  local username=$(get_username)
  local payload="{\"deviceId\":\"$device_id\",\"employeeEmail\":\"$username@example.com\",\"status\":\"deleted\",\"message\":\"Agent successfully removed from system\"}"
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    -d "$payload" \
    "$PING_ENDPOINT" 2>/dev/null
  
  log 1 "=========================================="
  log 1 "AUTO-ELIMINACIÓN COMPLETADA"
  log 1 "El agente se eliminará en 3 segundos..."
  log 1 "=========================================="
  
  # Mostrar notificación final
  osascript -e 'display notification "SoftCheck Agent eliminado exitosamente. El sistema se limpiará automáticamente." with title "SoftCheck Agent" sound name "Glass"' 2>/dev/null
  
  # Ejecutar script de auto-eliminación en segundo plano y terminar
  nohup "$self_delete_script" "$0" > /dev/null 2>&1 &
  
  # Terminar el proceso actual
  exit 0
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

# Función para procesar argumentos de línea de comandos
process_command_line_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --team)
        TEAM_NAME="$2"
        log 1 "Team configurado desde línea de comandos: $TEAM_NAME"
        update_endpoints
        shift 2
        ;;
      --diagnose)
        echo "Ejecutando diagnóstico de conexión y autenticación..."
        diagnose_authentication
        exit 0
        ;;
      --list-teams)
        echo "Obteniendo lista de teams disponibles..."
        local teams_response=$(curl -s -X GET \
          -H "Content-Type: application/json" \
          -H "X-API-KEY: $API_KEY" \
          -H "Accept: application/json" \
          -H "User-Agent: SoftCheck-Agent/1.0" \
          --connect-timeout 30 \
          "$BACKEND_URL/teams")
        
        if command -v jq &> /dev/null && echo "$teams_response" | jq empty 2>/dev/null; then
          echo "Teams disponibles:"
          echo "$teams_response" | jq -r '.[] | "  - \(.slug // .name) (\(.name // .slug))"' 2>/dev/null || echo "  No se pudieron parsear los teams"
        else
          echo "Error al obtener teams o respuesta no válida:"
          echo "$teams_response"
        fi
        exit 0
        ;;
      --help)
        echo "Uso: $0 [--team NOMBRE_EQUIPO] [--list-teams] [--diagnose] [--help]"
        echo ""
        echo "Opciones:"
        echo "  --team NOMBRE_EQUIPO    Especificar el nombre del equipo manualmente"
        echo "  --list-teams            Listar teams disponibles en el servidor"
        echo "  --diagnose              Ejecutar diagnóstico de conexión y autenticación"
        echo "  --help                  Mostrar esta ayuda"
        echo ""
        echo "Si no se especifica --team, el agente intentará detectar automáticamente"
        echo "el equipo desde el servidor o usará 'default' como fallback."
        echo ""
        echo "Ejemplos:"
        echo "  $0 --diagnose                      # Diagnosticar problemas"
        echo "  $0 --list-teams                    # Ver teams disponibles"
        echo "  $0 --team mi-empresa               # Usar team específico"
        echo "  $0                                 # Detección automática"
        exit 0
        ;;
      *)
        log 1 "Argumento desconocido: $1"
        log 1 "Use --help para ver las opciones disponibles"
        exit 1
        ;;
    esac
  done
}

# --- Iniciar el agente ---
# Procesar argumentos de línea de comandos
process_command_line_args "$@"

# Establecer hora de inicio para sincronización más precisa
SYNC_START_TIME=$(date +%s)
PING_INTERVAL=60  # Intervalo de ping en segundos

# Iniciar el daemon de sincronización
start_sync_daemon

# Mostrar información inicial del agente
print_agent_settings

# Ejecutar el monitor de instalaciones
run_monitor 