# WindowsInstallAgent.ps1
#
# Monitor de instalaciones para Windows
# Este agente monitorea continuamente los cambios en las aplicaciones instaladas,
# verifica nuevas instalaciones con un servidor central, y bloquea aplicaciones no autorizadas.
#
# Características:
# - Detección de nuevas aplicaciones instaladas
# - Verificación de software con un servidor central
# - Cuarentena de aplicaciones no autorizadas
# - Funcionamiento silencioso en segundo plano

# Variables de configuración
$script:BACKEND_URL = "http://localhost:4002/api"
$script:VERIFICATION_ENDPOINT = "$BACKEND_URL/validate_software"
$script:API_KEY = "305f98c40f6ab0224759d1725147ca1b"  # Debe coincidir con el valor en la base de datos
$script:PROGRAM_FILES = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}")
$script:SCAN_INTERVAL = 10  # segundos entre escaneos
$script:QUARANTINE_DIR = "$env:LOCALAPPDATA\AppQuarantine"
$script:SETTINGS_ENDPOINT = "$BACKEND_URL/settings"  # Endpoint para obtener ajustes
$script:STATUS_ENDPOINT = "$BACKEND_URL/agents/status"
$script:PING_ENDPOINT = "$BACKEND_URL/agents/ping"  # Endpoint para enviar pings
$script:SOFTWARE_STATUS_ENDPOINT = "$BACKEND_URL/software/status"  # Endpoint para verificar estado de aprobación

# Configuración del agente
$script:AGENT_STATUS = "active"      # active/inactive - Determina si el agente está funcionando
$script:AGENT_MODE = "active"        # active/passive - En modo pasivo solo monitorea sin tomar acciones
$script:AGENT_AUTO_UPDATE = $true    # Determina si el agente se actualiza automáticamente
$script:AGENT_CONFIG_FILE = "$env:LOCALAPPDATA\SoftCheck\agent_config.json"
$script:PENDING_APPS_FILE = "$env:LOCALAPPDATA\SoftCheck\pending_apps.json"

# Variable para controlar el nivel de verbosidad (0=silencioso, 1=normal, 2=detallado)
$script:VERBOSE_LEVEL = 2

# Variables para control de reintentos
$script:RETRY_INTERVAL = 300 # 5 minutos entre reintentos de verificación después de un fallo de auth
$script:AUTH_FAILURE_TIME = 0 # Tiempo del último fallo de autenticación
$script:AUTH_FAILURE_REPORTED = 0 # Para evitar mensajes repetitivos
$script:LAST_SYNC_TIME = 0 # Última vez que se sincronizó con el servidor

# Función para imprimir mensajes de log según el nivel de verbosidad
function Log {
    param (
        [int]$level,
        [string]$message
    )
    
    # Solo imprimir si el nivel de verbosidad actual es mayor o igual al nivel del mensaje
    if ($script:VERBOSE_LEVEL -ge $level) {
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message"
    }
}

# Función para imprimir las configuraciones actuales del agente
function Print-AgentSettings {
    # Obtener el tiempo desde la última sincronización exitosa
    $now = [int](Get-Date -UFormat %s)
    $sync_time_diff = $now - $script:LAST_SYNC_TIME
    $sync_status = "Nunca sincronizado"
    
    if ($script:LAST_SYNC_TIME -gt 0) {
        if ($sync_time_diff -lt 120) {
            $sync_status = "Sincronizado hace $sync_time_diff segundos"
        } else {
            $sync_status = "Sincronizado hace $([math]::Floor($sync_time_diff / 60)) minutos"
        }
    }
    
    # Determinar el estado de la conexión al servidor
    $connection_status = "DESCONECTADO"
    if ($script:LAST_SYNC_TIME -gt 0 -and $sync_time_diff -lt 300) {
        $connection_status = "CONECTADO"
    }
    
    Log 1 "========================================"
    Log 1 "  CONFIGURACIÓN ACTUAL DEL AGENTE"
    Log 1 "========================================"
    Log 1 " Status     : $($script:AGENT_STATUS) $(if ($script:AGENT_STATUS -eq "active") { "ACTIVO" } else { "INACTIVO" })"
    Log 1 " Mode       : $($script:AGENT_MODE) $(if ($script:AGENT_MODE -eq "active") { "ACTIVO" } else { "PASIVO" })"
    Log 1 " Device ID  : $(Get-DeviceId)"
    Log 1 " Servidor   : $($script:BACKEND_URL)"
    Log 1 " Conexión   : $connection_status"
    Log 1 "========================================"
}

# Asegurar que la carpeta de configuración existe
function Setup-ConfigDir {
    $configDir = "$env:LOCALAPPDATA\SoftCheck"
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    Log 2 "Carpeta de configuración configurada: $configDir"
}

# Verificar y cargar configuración guardada o crearla si no existe
function Load-OrCreateConfig {
    $device_id = Get-DeviceId
    $username = Get-Username
    
    # Inicializar variable para la última sincronización exitosa
    $script:LAST_SYNC_TIME = 0
    
    if (Test-Path $script:AGENT_CONFIG_FILE) {
        try {
            # Cargar configuración desde el archivo
            $config = Get-Content $script:AGENT_CONFIG_FILE | ConvertFrom-Json
            $script:AGENT_STATUS = $config.status
            $script:AGENT_MODE = $config.mode
            $script:AGENT_AUTO_UPDATE = $config.autoUpdate
            
            Log 2 "Configuración cargada desde archivo local"
            Print-AgentSettings
        }
        catch {
            Log 1 "Archivo de configuración corrupto. Restaurando desde backup o creando uno nuevo."
            
            # Intentar restaurar desde backup
            if (Test-Path "${script:AGENT_CONFIG_FILE}.backup") {
                try {
                    $config = Get-Content "${script:AGENT_CONFIG_FILE}.backup" | ConvertFrom-Json
                    $script:AGENT_STATUS = $config.status
                    $script:AGENT_MODE = $config.mode
                    $script:AGENT_AUTO_UPDATE = $config.autoUpdate
                    Log 2 "Configuración restaurada desde backup"
                }
                catch {
                    # Crear configuración por defecto
                    $script:AGENT_STATUS = "active"
                    $script:AGENT_MODE = "active"
                    $script:AGENT_AUTO_UPDATE = $true
                    Update-ConfigFile $device_id $username
                    Log 2 "Configuración por defecto creada"
                }
            }
            else {
                # Crear configuración por defecto
                $script:AGENT_STATUS = "active"
                $script:AGENT_MODE = "active"
                $script:AGENT_AUTO_UPDATE = $true
                Update-ConfigFile $device_id $username
                Log 2 "Configuración por defecto creada"
            }
            Print-AgentSettings
        }
    }
    else {
        # Crear configuración inicial
        $script:AGENT_STATUS = "active"
        $script:AGENT_MODE = "active"
        $script:AGENT_AUTO_UPDATE = $true
        Update-ConfigFile $device_id $username
        Log 2 "Configuración inicial creada"
        Print-AgentSettings
    }
    
    # Sincronizar con el servidor para obtener la configuración actual
    Sync-ConfigWithServer
}

# Sincronizar configuración con el servidor
function Sync-ConfigWithServer {
    $device_id = Get-DeviceId
    $username = Get-Username
    
    Log 2 "Sincronizando configuración con el servidor..."
    Log 2 "Device ID: $device_id"
    
    try {
        # Obtener configuración desde el servidor
        $response = Invoke-RestMethod -Uri $script:SETTINGS_ENDPOINT -Method Get -Headers @{
            "Content-Type" = "application/json"
            "X-API-KEY" = $script:API_KEY
            "Accept" = "application/json"
            "User-Agent" = "SoftCheck-Agent/1.0"
        } -TimeoutSec 30 -ErrorAction Stop
        
        # Extraer valores del JSON
        $isActive = $response.isActive
        $isActiveMode = $response.isActiveMode
        $autoUpdate = $response.autoUpdate
        
        # Guardar configuración anterior para comparar cambios
        $previous_status = $script:AGENT_STATUS
        $previous_mode = $script:AGENT_MODE
        $previous_auto_update = $script:AGENT_AUTO_UPDATE
        
        # Convertir true/false a active/inactive para status y mode
        if ($isActive) {
            $script:AGENT_STATUS = "active"
        } else {
            $script:AGENT_STATUS = "inactive"
        }
        
        if ($isActiveMode) {
            $script:AGENT_MODE = "active"
        } else {
            $script:AGENT_MODE = "passive"
        }
        
        $script:AGENT_AUTO_UPDATE = $autoUpdate
        
        # Verificar si hubo cambios en la configuración
        if ($previous_status -ne $script:AGENT_STATUS -or $previous_mode -ne $script:AGENT_MODE -or $previous_auto_update -ne $script:AGENT_AUTO_UPDATE) {
            Log 1 "Configuración actualizada: Status=$($script:AGENT_STATUS), Mode=$($script:AGENT_MODE)"
        }
        
        # Guardar configuración actualizada
        Update-ConfigFile $device_id $username
        
        # Establecer hora de última sincronización exitosa
        $script:LAST_SYNC_TIME = [int](Get-Date -UFormat %s)
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        Log 1 "No se pudo obtener la configuración del servidor: $errorMessage"
        return $false
    }
}

# Función para actualizar el archivo de configuración
function Update-ConfigFile {
    param (
        [string]$device_id,
        [string]$username
    )
    
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Crear JSON con la configuración actual
    $config = @{
        status = $script:AGENT_STATUS
        mode = $script:AGENT_MODE
        autoUpdate = $script:AGENT_AUTO_UPDATE
        deviceId = $device_id
        username = $username
        lastSync = $timestamp
    }
    
    # Asegurar que el directorio existe
    $configDir = [System.IO.Path]::GetDirectoryName($script:AGENT_CONFIG_FILE)
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    
    # Guardar al archivo de configuración
    $config | ConvertTo-Json | Set-Content -Path $script:AGENT_CONFIG_FILE -Force
    
    # También guardar a un archivo de respaldo
    $config | ConvertTo-Json | Set-Content -Path "${script:AGENT_CONFIG_FILE}.backup" -Force
    
    Log 2 "Archivo de configuración actualizado"
}

# Función para obtener el nombre de usuario actual
function Get-Username {
    return $env:USERNAME
}

# Función para obtener un ID único del dispositivo
function Get-DeviceId {
    try {
        # Intentar obtener el número de serie del BIOS
        $serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber
        if ($serial -and $serial -ne "") {
            return "SERIAL-$serial"
        }
    }
    catch {
        # Si hay error, intentar otro método
    }
    
    try {
        # Usar la dirección MAC de la primera interfaz de red como alternativa
        $mac = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | Select-Object -First 1).MACAddress
        if ($mac -and $mac -ne "") {
            return "MAC-$($mac.Replace(':', ''))"
        }
    }
    catch {
        # Si hay error, usar un identificador basado en el nombre del equipo
    }
    
    # Usar nombre del equipo como última opción
    return "PC-$env:COMPUTERNAME"
}

# Calcular hash SHA256 de un archivo
function Calculate-SHA256 {
    param (
        [string]$filePath
    )
    
    if (Test-Path $filePath -PathType Leaf) {
        try {
            $fileStream = [System.IO.File]::OpenRead($filePath)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $hashBytes = $sha256.ComputeHash($fileStream)
            $fileStream.Close()
            return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        }
        catch {
            return "no_disponible"
        }
    }
    else {
        return "no_disponible"
    }
}

# Asegurar que la carpeta de cuarentena existe
function Setup-Quarantine {
    if (-not (Test-Path $script:QUARANTINE_DIR)) {
        New-Item -Path $script:QUARANTINE_DIR -ItemType Directory -Force | Out-Null
    }
    Log 2 "Carpeta de cuarentena configurada: $script:QUARANTINE_DIR"
}

# Obtener versión de una aplicación
function Get-AppVersion {
    param (
        [string]$appPath,
        [string]$appName
    )
    
    try {
        # Intentar obtener versión del archivo ejecutable
        if (Test-Path "$appPath\$appName.exe") {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$appPath\$appName.exe")
            if ($versionInfo.FileVersion) {
                return $versionInfo.FileVersion
            }
        }
        
        # Buscar el primer archivo .exe en el directorio
        $exeFiles = Get-ChildItem -Path $appPath -Filter "*.exe" -File
        if ($exeFiles.Count -gt 0) {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exeFiles[0].FullName)
            if ($versionInfo.FileVersion) {
                return $versionInfo.FileVersion
            }
        }
    }
    catch {
        # Error al obtener versión
    }
    
    return "desconocida"
}

# Obtener la empresa desarrolladora de una aplicación
function Get-AppVendor {
    param (
        [string]$appPath,
        [string]$appName
    )
    
    try {
        # Intentar obtener fabricante del archivo ejecutable
        if (Test-Path "$appPath\$appName.exe") {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$appPath\$appName.exe")
            if ($versionInfo.CompanyName) {
                return $versionInfo.CompanyName
            }
        }
        
        # Buscar el primer archivo .exe en el directorio
        $exeFiles = Get-ChildItem -Path $appPath -Filter "*.exe" -File
        if ($exeFiles.Count -gt 0) {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exeFiles[0].FullName)
            if ($versionInfo.CompanyName) {
                return $versionInfo.CompanyName
            }
        }
    }
    catch {
        # Error al obtener fabricante
    }
    
    return "desconocido"
}

# Verificar si una aplicación está siendo ejecutada
function Is-AppRunning {
    param (
        [string]$appName
    )
    
    $processes = Get-Process -Name $appName -ErrorAction SilentlyContinue
    if ($processes -and $processes.Count -gt 0) {
        return $true
    }
    return $false
}

# Verificar firma digital de la aplicación
function Check-DigitalSignature {
    param (
        [string]$appPath,
        [string]$appName
    )
    
    try {
        # Intentar verificar firma del ejecutable principal
        if (Test-Path "$appPath\$appName.exe") {
            $signature = Get-AuthenticodeSignature -FilePath "$appPath\$appName.exe"
            if ($signature.Status -eq "Valid") {
                return $true
            }
        }
        
        # Buscar el primer archivo .exe en el directorio
        $exeFiles = Get-ChildItem -Path $appPath -Filter "*.exe" -File
        if ($exeFiles.Count -gt 0) {
            $signature = Get-AuthenticodeSignature -FilePath $exeFiles[0].FullName
            if ($signature.Status -eq "Valid") {
                return $true
            }
        }
    }
    catch {
        # Error al verificar firma
    }
    
    return $false
}

# Obtener fecha de instalación aproximada
function Get-InstallDate {
    param (
        [string]$appPath
    )
    
    try {
        if (Test-Path $appPath) {
            $folder = Get-Item $appPath
            return $folder.CreationTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
    catch {
        # Error al obtener fecha de instalación
    }
    
    return "null"
}

# Verificar si el software está autorizado con el servidor
function Verify-Software {
    param (
        [string]$appName,
        [string]$appVersion,
        [string]$appPath,
        [string]$sha256,
        [string]$username,
        [string]$deviceId,
        [string]$vendor,
        [string]$installDate,
        [bool]$isRunning,
        [bool]$digitalSignature
    )
    
    Log 1 "Verificando software: $appName $appVersion"
    
    # Crear objeto JSON para verificación
    $json = @{
        device_id = $deviceId
        user_id = $username
        software_name = $appName
        version = $appVersion
        vendor = $vendor
        install_date = $installDate
        install_path = $appPath
        install_method = "manual"
        last_executed = $null
        is_running = $isRunning
        digital_signature = $digitalSignature
        is_approved = $false
        detected_by = "windows_agent"
        sha256 = $sha256
        notes = $null
    } | ConvertTo-Json
    
    try {
        # Enviar solicitud de verificación y obtener respuesta
        $response = Invoke-RestMethod -Uri $script:VERIFICATION_ENDPOINT -Method Post -Headers @{
            "Content-Type" = "application/json"
            "X-API-KEY" = $script:API_KEY
            "Accept" = "application/json"
            "User-Agent" = "SoftCheck-Agent/1.0"
        } -Body $json -TimeoutSec 30 -ErrorAction Stop
        
        # Extraer software_id y status de la respuesta
        $softwareId = ""
        $status = "pending"
        
        if ($response.software) {
            $softwareId = $response.software.id
            $status = $response.software.status
            Log 2 "Software ID: $softwareId, Status: $status"
        }
        elseif ($response.softwareId) {
            $softwareId = $response.softwareId
            $isApproved = $response.isApproved
            
            if ($isApproved) {
                $status = "approved"
            }
            else {
                $status = "pending"
            }
            
            Log 2 "Software ID: $softwareId, IsApproved: $isApproved, Mapped Status: $status"
        }
        elseif ($response.success -eq $true) {
            $status = "approved"
        }
        
        # Si tenemos un ID de software y el estado es "pending", guardar en lista de pendientes
        if ($softwareId -and $status -eq "pending") {
            Add-ToPendingList $appName $appVersion $appPath $softwareId
        }
        
        Log 1 "Resultado de verificación: $status"
        
        # Retornar resultado según el status
        if ($status -eq "approved" -or $status -eq "whitelist") {
            return 0  # Aprobado
        }
        elseif ($status -eq "blacklist") {
            return 2  # Rechazado explícitamente
        }
        else {
            return 1  # Pendiente o desconocido
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Log 1 "Error al verificar software: $errorMessage"
        return 1  # Error, tratar como pendiente
    }
}

# Añadir una aplicación a la lista de pendientes
function Add-ToPendingList {
    param (
        [string]$appName,
        [string]$appVersion,
        [string]$appPath,
        [string]$softwareId
    )
    
    $timestamp = [int](Get-Date -UFormat %s)
    
    # Crear directorio de configuración si no existe
    $configDir = [System.IO.Path]::GetDirectoryName($script:PENDING_APPS_FILE)
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    
    # Crear el archivo JSON si no existe
    if (-not (Test-Path $script:PENDING_APPS_FILE)) {
        "[]" | Set-Content -Path $script:PENDING_APPS_FILE
    }
    
    try {
        # Leer el JSON actual
        $pendingApps = Get-Content -Path $script:PENDING_APPS_FILE | ConvertFrom-Json
        if (-not $pendingApps) {
            $pendingApps = @()
        }
        
        # Añadir la nueva aplicación al JSON
        $newEntry = @{
            software_id = $softwareId
            app_name = $appName
            app_version = $appVersion
            app_path = $appPath
            timestamp = $timestamp
        }
        
        $pendingApps += $newEntry
        $pendingApps | ConvertTo-Json | Set-Content -Path $script:PENDING_APPS_FILE
        
        Log 2 "Aplicación $appName añadida a la lista de pendientes"
    }
    catch {
        Log 1 "No se pudo añadir a la lista de pendientes: $_"
    }
}

# Verificar estado de aplicaciones pendientes
function Check-PendingApplications {
    Log 2 "Verificando aplicaciones pendientes..."
    
    # Verificar si hay aplicaciones pendientes
    if (-not (Test-Path $script:PENDING_APPS_FILE)) {
        Log 2 "No hay aplicaciones pendientes"
        return
    }
    
    try {
        # Leer la lista de aplicaciones pendientes
        $pendingApps = Get-Content -Path $script:PENDING_APPS_FILE | ConvertFrom-Json
        
        # Verificar si la lista está vacía
        if (-not $pendingApps -or $pendingApps.Count -eq 0) {
            Log 2 "No hay aplicaciones pendientes"
            return
        }
        
        Log 2 "$($pendingApps.Count) aplicaciones pendientes encontradas"
        
        # Verificar si ha pasado suficiente tiempo desde el último fallo de autenticación
        $now = [int](Get-Date -UFormat %s)
        if ($script:AUTH_FAILURE_TIME -gt 0 -and ($now - $script:AUTH_FAILURE_TIME) -lt $script:RETRY_INTERVAL) {
            # Si no ha pasado suficiente tiempo desde el último fallo, saltar verificación
            $waitTime = $script:RETRY_INTERVAL - ($now - $script:AUTH_FAILURE_TIME)
            
            # Reportar sólo una vez por ciclo de espera
            if ($script:AUTH_FAILURE_REPORTED -eq 0) {
                Log 1 "Esperando $waitTime segundos antes de reintentar verificaciones (problema de autenticación)"
                $script:AUTH_FAILURE_REPORTED = 1
            }
            return
        }
        
        # Resetear el flag de reporte
        $script:AUTH_FAILURE_REPORTED = 0
        
        # Array para almacenar IDs de aplicaciones a eliminar de la lista
        $appsToRemove = @()
        $authFailed = $false
        
        # Iterar sobre cada aplicación pendiente
        foreach ($app in $pendingApps) {
            $softwareId = $app.software_id
            $appName = $app.app_name
            
            Log 2 "Verificando estado de $appName (ID: $softwareId)..."
            
            try {
                # Verificar estado actual con el servidor
                $statusResponse = Invoke-RestMethod -Uri "$($script:SOFTWARE_STATUS_ENDPOINT)/$softwareId" -Method Get -Headers @{
                    "Content-Type" = "application/json"
                    "X-API-KEY" = $script:API_KEY
                    "Accept" = "application/json"
                    "User-Agent" = "SoftCheck-Agent/1.0"
                } -TimeoutSec 30 -ErrorAction Stop
                
                # Extraer el estado actual
                $currentStatus = $statusResponse.status
                if (-not $currentStatus) {
                    $currentStatus = "pending"
                }
                
                $rejectionReason = $statusResponse.reason
                if (-not $rejectionReason) {
                    $rejectionReason = "No cumple con las políticas de seguridad"
                }
                
                Log 2 "Estado actual: $currentStatus"
                
                # Actuar según el estado
                if ($currentStatus -eq "approved" -or $currentStatus -eq "whitelist") {
                    Log 1 "$appName ha sido aprobado. Restaurando permisos de ejecución..."
                    
                    # Restaurar permisos de ejecución
                    if (Restore-AppExecution $app.app_path) {
                        Log 1 "Permisos restaurados para $appName"
                        $appsToRemove += $softwareId
                    }
                    else {
                        Show-Dialog "Error de Restauración" "El software $appName ha sido aprobado, pero hubo un problema al restaurar sus permisos."
                    }
                }
                elseif ($currentStatus -eq "rejected" -or $currentStatus -eq "blacklist" -or $currentStatus -eq "denied") {
                    Log 1 "$appName ha sido rechazado. Eliminando..."
                    
                    # Mostrar el motivo del rechazo al usuario
                    Show-Dialog "Software Rechazado" "El software $appName ha sido rechazado.`n`nRazón: $rejectionReason"
                    
                    # Eliminar la aplicación
                    if (Delete-Application $app.app_path) {
                        Log 1 "Aplicación $appName eliminada correctamente"
                        $appsToRemove += $softwareId
                    }
                    else {
                        Show-Dialog "Error de Eliminación" "El software $appName ha sido rechazado, pero hubo un problema al eliminarlo."
                    }
                }
                else {
                    Log 2 "$appName sigue pendiente"
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                
                # Verificar si es un problema de autenticación
                if ($errorMessage -like "*401*" -or $errorMessage -like "*Unauthorized*" -or $errorMessage -like "*login*") {
                    # Si es el primer fallo de autenticación en este ciclo
                    if (-not $authFailed) {
                        Log 1 "ADVERTENCIA: Posible problema de autenticación. Intentando renovar la conexión."
                        
                        # Intentar renovar la conexión con el servidor
                        Ping-Server
                        Sync-ConfigWithServer
                        
                        # Registrar tiempo de fallo para implementar backoff
                        $script:AUTH_FAILURE_TIME = [int](Get-Date -UFormat %s)
                        $authFailed = $true
                    }
                    
                    # La aplicación continúa pendiente
                    Log 2 "$appName sigue pendiente (problema de autenticación)"
                }
                else {
                    Log 1 "Error al verificar el estado de $appName: $errorMessage"
                    Log 2 "$appName sigue pendiente (error de verificación)"
                }
            }
        }
        
        # Eliminar aplicaciones procesadas de la lista de pendientes
        if ($appsToRemove.Count -gt 0) {
            $updatedPendingApps = $pendingApps | Where-Object { $appsToRemove -notcontains $_.software_id }
            $updatedPendingApps | ConvertTo-Json | Set-Content -Path $script:PENDING_APPS_FILE
        }
        
        Log 2 "Verificación de aplicaciones pendientes completada"
    }
    catch {
        Log 1 "Error al procesar aplicaciones pendientes: $_"
    }
}

# Mover aplicación a cuarentena
function Move-ToQuarantine {
    param (
        [string]$appPath
    )
    
    $appName = [System.IO.Path]::GetFileName($appPath)
    $quarantinePath = Join-Path -Path $script:QUARANTINE_DIR -ChildPath $appName
    
    try {
        # Crear directorio de cuarentena si no existe
        if (-not (Test-Path $script:QUARANTINE_DIR)) {
            New-Item -Path $script:QUARANTINE_DIR -ItemType Directory -Force | Out-Null
        }
        
        # Eliminar destino si ya existe
        if (Test-Path $quarantinePath) {
            Remove-Item -Path $quarantinePath -Recurse -Force
        }
        
        # Mover aplicación a cuarentena
        Move-Item -Path $appPath -Destination $script:QUARANTINE_DIR -Force
        
        Log 2 "Aplicación movida a cuarentena: $quarantinePath"
        return $quarantinePath
    }
    catch {
        Log 1 "Error al mover a cuarentena: $appPath - $_"
        return $null
    }
}

# Restaurar aplicación desde cuarentena
function Restore-FromQuarantine {
    param (
        [string]$quarantinePath
    )
    
    $appName = [System.IO.Path]::GetFileName($quarantinePath)
    $destinationPath = Join-Path -Path $script:PROGRAM_FILES[0] -ChildPath $appName
    
    try {
        # Eliminar destino si ya existe
        if (Test-Path $destinationPath) {
            Remove-Item -Path $destinationPath -Recurse -Force
        }
        
        # Mover aplicación desde cuarentena
        Move-Item -Path $quarantinePath -Destination $destinationPath -Force
        
        Log 2 "Aplicación restaurada desde cuarentena: $destinationPath"
        return $true
    }
    catch {
        Log 1 "Error al restaurar desde cuarentena: $quarantinePath - $_"
        return $false
    }
}

# Eliminar permanentemente una aplicación
function Delete-Application {
    param (
        [string]$appPath
    )
    
    try {
        # Verificar si la aplicación existe
        if (Test-Path $appPath) {
            # Intentar desinstalar si hay un desinstalador
            $uninstaller = Get-ChildItem -Path $appPath -Recurse -Include "uninstall.exe", "uninst.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($uninstaller) {
                Log 2 "Intentando desinstalar usando: $($uninstaller.FullName)"
                Start-Process -FilePath $uninstaller.FullName -ArgumentList "/S", "/SILENT", "/VERYSILENT", "/NORESTART" -Wait
            }
            
            # Eliminar directorio
            Remove-Item -Path $appPath -Recurse -Force
            Log 2 "Aplicación eliminada: $appPath"
            return $true
        }
        else {
            Log 2 "Aplicación ya no existe: $appPath"
            return $true
        }
    }
    catch {
        Log 1 "Error al eliminar aplicación: $appPath - $_"
        return $false
    }
}

# Mostrar notificación en Windows
function Show-Notification {
    param (
        [string]$title,
        [string]$message
    )
    
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        
        $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
        $textNodes = $xml.GetElementsByTagName("text")
        
        $textNodes.Item(0).InnerText = $title
        $textNodes.Item(1).InnerText = $message
        
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("SoftCheck Agent").Show($toast)
    }
    catch {
        # Método alternativo si Windows.UI.Notifications no está disponible
        Add-Type -AssemblyName System.Windows.Forms
        $global:balloon = New-Object System.Windows.Forms.NotifyIcon
        $path = Get-Process -id $pid | Select-Object -ExpandProperty Path
        $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.BalloonTipTitle = $title
        $balloon.BalloonTipText = $message
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(5000)
    }
}

# Mostrar diálogo al usuario
function Show-Dialog {
    param (
        [string]$title,
        [string]$message
    )
    
    try {
        Add-Type -AssemblyName PresentationCore,PresentationFramework
        [System.Windows.MessageBox]::Show($message, $title, 'OK', 'Warning')
    }
    catch {
        # Método alternativo si WPF no está disponible
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}

# Registrar aplicaciones instaladas en Windows
function Get-CurrentApps {
    $installedApps = @()
    
    # Buscar aplicaciones en directorios estándar de programas
    foreach ($programDir in $script:PROGRAM_FILES) {
        if (Test-Path $programDir) {
            Get-ChildItem -Path $programDir -Directory | ForEach-Object {
                $installedApps += $_.Name
            }
        }
    }
    
    # Obtener aplicaciones instaladas desde el registro (para aplicaciones modernas y tradicionales)
    try {
        # Aplicaciones clásicas (x86)
        Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | 
        Where-Object { $_.DisplayName } | 
        ForEach-Object { $installedApps += $_.DisplayName }
        
        # Aplicaciones clásicas (x64)
        Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object { $_.DisplayName } | 
        ForEach-Object { $installedApps += $_.DisplayName }
        
        # Aplicaciones de Microsoft Store (por usuario)
        Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object { $_.DisplayName } | 
        ForEach-Object { $installedApps += $_.DisplayName }
    }
    catch {
        Log 1 "Error al obtener aplicaciones del registro: $_"
    }
    
    # Eliminar duplicados y retornar
    return $installedApps | Sort-Object | Get-Unique
}

# Verificar si una aplicación existe en la lista
function App-Exists {
    param (
        [string]$appName,
        [array]$appList
    )
    
    return $appList -contains $appName
}

# Restringir permisos de ejecución de una aplicación
function Restrict-AppExecution {
    param (
        [string]$appPath
    )
    
    Log 1 "Restringiendo permisos de ejecución para: $appPath"
    
    try {
        # Verificar que la aplicación existe
        if (-not (Test-Path $appPath)) {
            Log 1 "ERROR: La aplicación no existe: $appPath"
            return $false
        }
        
        # Crear directorio de metadatos
        $metadataDir = Join-Path -Path $appPath -ChildPath ".softcheck"
        if (-not (Test-Path $metadataDir)) {
            New-Item -Path $metadataDir -ItemType Directory -Force | Out-Null
        }
        
        # Buscar archivos ejecutables en la aplicación
        $exeFiles = Get-ChildItem -Path $appPath -Filter "*.exe" -Recurse -File
        
        # Guardar información de los ejecutables
        $exeInfo = @()
        foreach ($exe in $exeFiles) {
            try {
                # Obtener propietario y permisos actuales
                $acl = Get-Acl -Path $exe.FullName
                $owner = $acl.Owner
                
                # Guardar información del ejecutable
                $exeInfo += [PSCustomObject]@{
                    Path = $exe.FullName
                    Owner = $owner
                    ACL = $acl
                }
                
                # Crear un nuevo ACL para restringir acceso
                $newAcl = New-Object System.Security.AccessControl.FileSecurity
                $newAcl.SetOwner((New-Object System.Security.Principal.NTAccount("SYSTEM")))
                
                # Denegar ejecución a todos los usuarios excepto Administradores
                $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    (New-Object System.Security.Principal.NTAccount("Users")),
                    "ReadAndExecute",
                    "Deny"
                )
                $newAcl.AddAccessRule($denyRule)
                
                # Aplicar las restricciones
                Set-Acl -Path $exe.FullName -AclObject $newAcl -ErrorAction Stop
                
                Log 2 "Restringidos permisos para: $($exe.FullName)"
            }
            catch {
                Log 1 "Error al restringir permisos para $($exe.FullName): $_"
            }
        }
        
        # Guardar la información para restauración posterior
        $exeInfo | ConvertTo-Json | Set-Content -Path (Join-Path -Path $metadataDir -ChildPath "exe_perms.json")
        
        # Crear archivo de bloqueo
        "BLOQUEADO_POR_SOFTCHECK" | Set-Content -Path (Join-Path -Path $metadataDir -ChildPath "blockedApp.txt")
        
        Log 1 "Permisos restringidos para: $appPath"
        return $true
    }
    catch {
        Log 1 "Error general al restringir permisos: $_"
        return $false
    }
}

# Restaurar permisos de ejecución de una aplicación
function Restore-AppExecution {
    param (
        [string]$appPath
    )
    
    Log 1 "Restaurando permisos de ejecución para: $appPath"
    
    try {
        # Verificar que la aplicación existe
        if (-not (Test-Path $appPath)) {
            Log 1 "ERROR: La aplicación no existe: $appPath"
            return $false
        }
        
        # Verificar directorio de metadatos
        $metadataDir = Join-Path -Path $appPath -ChildPath ".softcheck"
        $permsFile = Join-Path -Path $metadataDir -ChildPath "exe_perms.json"
        
        if (Test-Path $permsFile) {
            # Cargar información de los ejecutables
            $exeInfo = Get-Content -Path $permsFile | ConvertFrom-Json
            
            # Restaurar permisos originales
            foreach ($exe in $exeInfo) {
                if (Test-Path $exe.Path) {
                    try {
                        # Restaurar ACL original
                        Set-Acl -Path $exe.Path -AclObject $exe.ACL -ErrorAction Stop
                        Log 2 "Restaurados permisos para: $($exe.Path)"
                    }
                    catch {
                        Log 1 "Error al restaurar permisos para $($exe.Path): $_"
                        
                        # Intentar método alternativo: dar permisos completos a todos
                        try {
                            $newAcl = New-Object System.Security.AccessControl.FileSecurity
                            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                                "Everyone",
                                "FullControl",
                                "Allow"
                            )
                            $newAcl.AddAccessRule($rule)
                            Set-Acl -Path $exe.Path -AclObject $newAcl -ErrorAction Stop
                            Log 2 "Aplicado método alternativo para: $($exe.Path)"
                        }
                        catch {
                            Log 1 "Error en método alternativo para $($exe.Path): $_"
                        }
                    }
                }
                else {
                    Log 1 "ADVERTENCIA: Archivo no encontrado: $($exe.Path)"
                }
            }
        }
        else {
            # Si no hay archivo de permisos, conceder permisos completos a todos los EXE
            Log 1 "Archivo de permisos no encontrado, usando método alternativo"
            $exeFiles = Get-ChildItem -Path $appPath -Filter "*.exe" -Recurse -File
            
            foreach ($exe in $exeFiles) {
                try {
                    $acl = New-Object System.Security.AccessControl.FileSecurity
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        "Everyone",
                        "FullControl",
                        "Allow"
                    )
                    $acl.AddAccessRule($rule)
                    Set-Acl -Path $exe.FullName -AclObject $acl -ErrorAction Stop
                    Log 2 "Concedidos permisos completos a: $($exe.FullName)"
                }
                catch {
                    Log 1 "Error al conceder permisos a $($exe.FullName): $_"
                }
            }
        }
        
        # Eliminar archivo de bloqueo
        $blockFile = Join-Path -Path $metadataDir -ChildPath "blockedApp.txt"
        if (Test-Path $blockFile) {
            Remove-Item -Path $blockFile -Force
        }
        
        # Eliminar directorio de metadatos
        if (Test-Path $metadataDir) {
            Remove-Item -Path $metadataDir -Recurse -Force
        }
        
        Log 1 "Permisos restaurados para: $appPath"
        return $true
    }
    catch {
        Log 1 "Error general al restaurar permisos: $_"
        return $false
    }
}

# Enviar ping al servidor para actualizar estado de actividad
function Ping-Server {
    $deviceId = Get-DeviceId
    $username = Get-Username
    
    Log 2 "Enviando ping al servidor..."
    
    # Construir payload con información del agente
    $payload = @{
        deviceId = $deviceId
        employeeEmail = "$username@example.com"
        status = $script:AGENT_STATUS
    } | ConvertTo-Json
    
    try {
        # Enviar ping al servidor
        $pingResponse = Invoke-RestMethod -Uri $script:PING_ENDPOINT -Method Post -Headers @{
            "Content-Type" = "application/json"
            "X-API-KEY" = $script:API_KEY
            "Accept" = "application/json"
            "User-Agent" = "SoftCheck-Agent/1.0"
        } -Body $payload -TimeoutSec 30 -ErrorAction Stop
        
        # Verificar si la respuesta fue exitosa
        if ($pingResponse.success -eq $true) {
            # Actualizar la última sincronización exitosa
            $script:LAST_SYNC_TIME = [int](Get-Date -UFormat %s)
            
            # Verificar si se debe actualizar el agente
            if ($pingResponse.shouldUpdate -eq $true) {
                Log 1 "El servidor indica que se debe actualizar el agente"
                Check-ForUpdates
            }
            
            return $true
        }
        else {
            Log 1 "Error en la respuesta del servidor"
            return $false
        }
    }
    catch {
        Log 1 "Error al enviar ping al servidor: $_"
        return $false
    }
}

# Verificar actualizaciones del agente
function Check-ForUpdates {
    Log 2 "Verificando actualizaciones del agente..."
    
    if ($script:AGENT_AUTO_UPDATE -eq $true) {
        try {
            # Obtener la versión actual del script (simulada por ahora)
            $currentVersion = "1.0.0"
            
            # Verificar con el servidor si hay una nueva versión
            $updateResponse = Invoke-RestMethod -Uri "$($script:BACKEND_URL)/agents/updates" -Method Get -Headers @{
                "X-API-KEY" = $script:API_KEY
                "User-Agent" = "SoftCheck-Agent/1.0"
            } -Body @{
                version = $currentVersion
                deviceId = Get-DeviceId
            } -TimeoutSec 30 -ErrorAction Stop
            
            # Comprobar si hay actualizaciones disponibles
            if ($updateResponse.updateAvailable -eq $true) {
                $updateUrl = $updateResponse.updateUrl
                
                # Descargar actualización
                Log 1 "Actualizando el agente a la nueva versión..."
                Invoke-WebRequest -Uri $updateUrl -OutFile "$env:TEMP\agent_update.ps1"
                
                if (Test-Path "$env:TEMP\agent_update.ps1") {
                    # Crear un script que sustituya el actual con el nuevo
                    $replaceScript = @"
# Esperar a que el proceso actual termine
Start-Sleep -Seconds 2
# Reemplazar el script actual con la nueva versión
Copy-Item -Path "$env:TEMP\agent_update.ps1" -Destination "$PSCommandPath" -Force
# Limpiar archivos temporales
Remove-Item -Path "$env:TEMP\agent_update.ps1" -Force
Remove-Item -Path "$env:TEMP\replace_agent.ps1" -Force
# Reiniciar el agente
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -WindowStyle Hidden
exit
"@
                    
                    Set-Content -Path "$env:TEMP\replace_agent.ps1" -Value $replaceScript
                    
                    # Ejecutar el script de reemplazo en segundo plano y salir
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$env:TEMP\replace_agent.ps1`"" -WindowStyle Hidden
                    Log 1 "Agente actualizado. Reiniciando..."
                    exit
                }
            }
            else {
                Log 2 "El agente está actualizado"
            }
        }
        catch {
            Log 1 "Error al verificar actualizaciones: $_"
        }
    }
}

# Procesar una nueva aplicación detectada
function Process-NewApplication {
    param (
        [string]$appName,
        [string]$appPath
    )
    
    # Si el agente está inactivo, no procesar nuevas aplicaciones
    if ($script:AGENT_STATUS -eq "inactive") {
        Log 1 "Agente inactivo. Detectada nueva aplicación $appName pero no se tomará ninguna acción"
        return
    }
    
    # Recopilar información
    $appVersion = Get-AppVersion $appPath $appName
    $username = Get-Username
    $deviceId = Get-DeviceId
    $vendor = Get-AppVendor $appPath $appName
    $installDate = Get-InstallDate $appPath
    $isRunning = Is-AppRunning $appName
    $digitalSignature = Check-DigitalSignature $appPath $appName
    
    # Buscar el ejecutable principal para calcular hash
    $mainExecutable = ""
    $exeFiles = Get-ChildItem -Path $appPath -Filter "*.exe" -File | Select-Object -First 1
    if ($exeFiles) {
        $mainExecutable = $exeFiles.FullName
    }
    
    $sha256 = "no_disponible"
    if ($mainExecutable -and (Test-Path $mainExecutable)) {
        $sha256 = Calculate-SHA256 $mainExecutable
    }
    
    # Mostrar diálogo informativo inicial
    $dialogText = "Se ha detectado la instalación de una nueva aplicación: $appName`n`nVersión: $appVersion`nDesarrollador: $vendor`nRuta: $appPath`nSHA256: $sha256`nUsuario: $username"
    Show-Dialog "Instalación Detectada" $dialogText
    
    # En modo pasivo, solo registrar la aplicación sin bloquearla
    if ($script:AGENT_MODE -eq "passive") {
        Log 1 "Modo pasivo. Detectada nueva aplicación $appName, se registrará sin bloquear"
        # Verificar si el software está autorizado (solo para registrar en el servidor)
        Verify-Software $appName $appVersion $appPath $sha256 $username $deviceId $vendor $installDate $isRunning $digitalSignature
        return
    }
    
    # En modo activo, restringir permisos de ejecución temporalmente
    Log 1 "Modo activo. Restringiendo ejecución de $appName temporalmente"
    Restrict-AppExecution $appPath
    
    # Verificar primero si el software ya existe en la base de datos
    $existingStatus = Check-SoftwareDatabase $appName $appVersion $deviceId
    
    if ($existingStatus.exists) {
        # Software encontrado en la base de datos
        $dbStatus = $existingStatus.status
        $softwareId = $existingStatus.softwareId
        
        if ($dbStatus -eq "approved" -or $dbStatus -eq "whitelist") {
            # Software ya aprobado en la base de datos
            Log 1 "$appName está en la base de datos y aprobado. Restaurando permisos"
            Restore-AppExecution $appPath
            Log 1 "Aplicación $appName aprobada y lista para usar"
        }
        elseif ($dbStatus -eq "rejected" -or $dbStatus -eq "blacklist" -or $dbStatus -eq "denied") {
            # Software ya rechazado en la base de datos
            Log 1 "$appName está en la base de datos y rechazado. Eliminando"
            
            # Obtener razón de rechazo si está disponible
            $rejectionReason = $existingStatus.reason
            if (-not $rejectionReason) {
                $rejectionReason = "No cumple con las políticas de seguridad"
            }
            
            # Mostrar mensaje al usuario
            Show-Dialog "Software No Autorizado" "El software $appName no está permitido por motivos de seguridad:`n`n$rejectionReason`n`nLa aplicación será eliminada."
            
            # Eliminar la aplicación
            if (Delete-Application $appPath) {
                Log 1 "Aplicación $appName eliminada correctamente"
            }
            else {
                Log 1 "Error al eliminar la aplicación $appName"
                Show-Dialog "Error" "No se pudo eliminar completamente la aplicación. Por favor, contacte con soporte técnico."
            }
        }
        else {
            # Software en estado pendiente o desconocido
            Log 1 "$appName está en la base de datos con estado $dbStatus. Manteniendo bloqueada"
            Show-Dialog "Software Pendiente" "El software $appName requiere aprobación. Se mantiene bloqueado hasta completar el análisis de seguridad"
        }
    }
    else {
        # Software no encontrado en la base de datos, se requiere verificación completa
        Show-Dialog "Verificación de Software" "El software $appName no está registrado. Se iniciará el proceso de verificación.`n`nEste proceso tomará aproximadamente 10 segundos"
        
        # Verificar si el software está autorizado con el proceso completo
        $verificationResult = Verify-Software $appName $appVersion $appPath $sha256 $username $deviceId $vendor $installDate $isRunning $digitalSignature
        
        if ($verificationResult -eq 0) {
            # Software aprobado (whitelist)
            Log 1 "$appName ha sido aprobado. Restaurando permisos de ejecución"
            Restore-AppExecution $appPath
        }
        elseif ($verificationResult -eq 2) {
            # Software rechazado (blacklist)
            Log 1 "$appName ha sido rechazado. Eliminando"
            
            # Intentar obtener la razón del rechazo
            $reason = "No cumple con las políticas de seguridad"
            
            # Informar al usuario
            Show-Dialog "Software No Permitido" "La instalación de $appName ha sido bloqueada.`n`nRazón: $reason"
            
            # Eliminar la aplicación
            if (Delete-Application $appPath) {
                Log 1 "Aplicación $appName eliminada correctamente"
            }
            else {
                Log 1 "Error al eliminar la aplicación $appName"
                Show-Dialog "Error" "No se pudo eliminar completamente la aplicación. Por favor, contacte con soporte técnico."
            }
        }
        else {
            # Software en estado pendiente
            Log 1 "$appName necesita aprobación manual. Manteniendo bloqueada"
            Show-Dialog "Software Pendiente" "El software $appName requiere aprobación. Se mantiene bloqueado hasta que se complete el análisis de seguridad"
            
            # Registrar en la lista de pendientes
            Add-ToPendingList $appName $appVersion $appPath $softwareId
        }
    }
}

# Verificar si el software ya existe en la base de datos
function Check-SoftwareDatabase {
    param (
        [string]$softwareName,
        [string]$version,
        [string]$deviceId
    )
    
    Log 2 "Verificando si $softwareName $version ya existe en la base de datos..."
    
    # Construir el endpoint para la consulta
    $name = $softwareName -replace ' ','%20' -replace '\+','%2B' -replace '&','%26'
    $ver = $version -replace ' ','%20' -replace '\+','%2B' -replace '&','%26'
    $endpoint = "$($script:BACKEND_URL)/software/exists?name=$name&version=$ver&deviceId=$deviceId"
    
    try {
        # Realizar la consulta al servidor
        $response = Invoke-RestMethod -Uri $endpoint -Method Get -Headers @{
            "Content-Type" = "application/json"
            "X-API-KEY" = $script:API_KEY
            "Accept" = "application/json"
            "User-Agent" = "SoftCheck-Agent/1.0"
        } -TimeoutSec 30 -ErrorAction Stop
        
        # Extraer información relevante
        $exists = $response.exists
        $softwareId = $response.softwareId
        $status = $response.status
        
        if ($exists -eq $true -and $softwareId) {
            Log 2 "Software encontrado en la base de datos. ID: $softwareId, Estado: $status"
            return @{
                exists = $true
                softwareId = $softwareId
                status = $status
                reason = $response.reason
            }
        }
        else {
            Log 2 "Software no encontrado en la base de datos"
            return @{
                exists = $false
                softwareId = ""
                status = "unknown"
                reason = ""
            }
        }
    }
    catch {
        Log 1 "Error al verificar en base de datos: $_"
        return @{
            exists = $false
            softwareId = ""
            status = "unknown"
            reason = ""
        }
    }
}

# Sincronizar configuración periódicamente en segundo plano
function Start-SyncDaemon {
    $syncJob = {
        param($syncConfig)
        
        # Extraer variables del objeto de configuración
        $BACKEND_URL = $syncConfig.BACKEND_URL
        $PING_ENDPOINT = $syncConfig.PING_ENDPOINT
        $API_KEY = $syncConfig.API_KEY
        $VERBOSE_LEVEL = $syncConfig.VERBOSE_LEVEL
        $AGENT_STATUS = $syncConfig.AGENT_STATUS
        $deviceId = $syncConfig.deviceId
        $username = $syncConfig.username
        
        function SyncLog {
            param (
                [int]$level,
                [string]$message
            )
            
            if ($VERBOSE_LEVEL -ge $level) {
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Write-Host "$timestamp - SYNC: $message"
            }
        }
        
        function SendPing {
            SyncLog 2 "Enviando ping al servidor..."
            
            # Construir payload con información del agente
            $payload = @{
                deviceId = $deviceId
                employeeEmail = "$username@example.com"
                status = $AGENT_STATUS
            } | ConvertTo-Json
            
            try {
                # Enviar ping al servidor
                $pingResponse = Invoke-RestMethod -Uri $PING_ENDPOINT -Method Post -Headers @{
                    "Content-Type" = "application/json"
                    "X-API-KEY" = $API_KEY
                    "Accept" = "application/json"
                    "User-Agent" = "SoftCheck-Agent/1.0"
                } -Body $payload -TimeoutSec 30 -ErrorAction Stop
                
                # Verificar si la respuesta fue exitosa
                if ($pingResponse.success -eq $true) {
                    SyncLog 1 "Ping exitoso: Estado del agente actualizado en el servidor"
                    return $true
                }
                else {
                    SyncLog 1 "Error en la respuesta del servidor"
                    return $false
                }
            }
            catch {
                SyncLog 1 "Error al enviar ping al servidor: $_"
                return $false
            }
        }
        
        # Bucle principal del daemon de sincronización
        SyncLog 1 "Daemon de sincronización iniciado"
        
        while ($true) {
            # Registrar tiempo de inicio de ciclo
            $cycleStart = [int](Get-Date -UFormat %s)
            
            # Enviar ping al servidor para actualizar estado de actividad
            SendPing
            
            # Calcular tiempo transcurrido en este ciclo
            $cycleEnd = [int](Get-Date -UFormat %s)
            $cycleDuration = $cycleEnd - $cycleStart
            
            # Calcular tiempo de espera para mantener intervalo preciso
            $waitTime = 60 - $cycleDuration # Intervalo de 1 minuto
            
            # Asegurar que waitTime no sea negativo
            if ($waitTime -lt 1) {
                $waitTime = 1
            }
            
            SyncLog 1 "Próximo ping en $waitTime segundos..."
            
            # Esperar para el siguiente ciclo
            Start-Sleep -Seconds $waitTime
        }
    }
    
    # Preparar configuración para el trabajo en segundo plano
    $syncConfig = @{
        BACKEND_URL = $script:BACKEND_URL
        PING_ENDPOINT = $script:PING_ENDPOINT
        API_KEY = $script:API_KEY
        VERBOSE_LEVEL = $script:VERBOSE_LEVEL
        AGENT_STATUS = $script:AGENT_STATUS
        deviceId = Get-DeviceId
        username = Get-Username
    }
    
    # Iniciar el job en segundo plano
    Start-Job -ScriptBlock $syncJob -ArgumentList $syncConfig | Out-Null
    Log 2 "Daemon de sincronización iniciado en segundo plano"
}

# Función principal que ejecuta el ciclo de monitoreo
function Run-Monitor {
    Log 1 "Iniciando monitor de instalaciones..."
    
    # Configurar carpetas necesarias
    Setup-Quarantine
    Setup-ConfigDir
    
    # Cargar o crear configuración
    Load-OrCreateConfig
    
    # Verificar actualizaciones del agente
    Check-ForUpdates
    
    # Variables para controlar el estado del monitor
    $monitoringActive = $true
    $initialApps = $null
    
    # Mostrar notificación de inicio
    Show-Notification "Monitor de Instalaciones" "Monitor de instalaciones iniciado"
    
    # Iniciar bucle principal que permanece activo incluso cuando el agente está inactivo
    while ($true) {
        # Comprobar estado actual del agente
        if ($script:AGENT_STATUS -eq "inactive" -and $monitoringActive -eq $true) {
            Log 1 "Agente configurado como inactivo. Entrando en modo espera"
            $monitoringActive = $false
            Show-Notification "Monitor de Instalaciones" "Agente inactivo - modo espera activado"
        }
        elseif ($script:AGENT_STATUS -eq "active" -and $monitoringActive -eq $false) {
            Log 1 "Agente reactivado. Retomando monitorización"
            $monitoringActive = $true
            Show-Notification "Monitor de Instalaciones" "Agente reactivado en modo $($script:AGENT_MODE)"
            # Reinicializar la lista de aplicaciones para evitar alertas de aplicaciones instaladas durante inactividad
            $initialApps = Get-CurrentApps
        }
        
        # Si el agente está activo, realizar el monitoreo normal
        if ($monitoringActive -eq $true) {
            # Si es la primera ejecución, inicializar la lista de aplicaciones
            if ($null -eq $initialApps) {
                $initialApps = Get-CurrentApps
                Log 1 "Se han detectado $($initialApps.Count) aplicaciones iniciales"
            }
            
            # Verificar aplicaciones pendientes
            Check-PendingApplications
            
            # Obtener lista actual de aplicaciones
            $currentApps = Get-CurrentApps
            
            # Buscar nuevas aplicaciones
            foreach ($app in $currentApps) {
                if ($initialApps -notcontains $app) {
                    Log 1 "Nueva aplicación detectada: $app"
                    
                    # Determinar la ruta de la aplicación
                    $appPath = $null
                    foreach ($programDir in $script:PROGRAM_FILES) {
                        $testPath = Join-Path -Path $programDir -ChildPath $app
                        if (Test-Path $testPath) {
                            $appPath = $testPath
                            break
                        }
                    }
                    
                    # Si se encontró la ruta, procesar la aplicación
                    if ($appPath) {
                        Process-NewApplication $app $appPath
                    }
                    else {
                        Log 1 "No se pudo determinar la ruta de instalación para: $app"
                    }
                    
                    # Actualizar lista de aplicaciones conocidas
                    $initialApps += $app
                }
            }
            
            # Esperar antes del siguiente escaneo (intervalo normal para monitoreo activo)
            Start-Sleep -Seconds $script:SCAN_INTERVAL
        }
        else {
            # En modo inactivo, esperar el mismo intervalo que el daemon de sincronización
            Start-Sleep -Seconds 60
        }
    }
}

# Instalar como servicio
function Install-AsService {
    Log 1 "Instalando como servicio..."
    
    try {
        # Verificar si ya existe el servicio
        $existingService = Get-Service -Name "SoftCheckAgent" -ErrorAction SilentlyContinue
        if ($existingService) {
            Log 1 "El servicio ya existe. Deteniéndolo antes de reinstalar..."
            Stop-Service -Name "SoftCheckAgent" -Force -ErrorAction SilentlyContinue
            
            # Darle tiempo a detenerse
            Start-Sleep -Seconds 5
            
            # Intentar eliminar el servicio existente
            sc.exe delete "SoftCheckAgent" | Out-Null
            Start-Sleep -Seconds 3
        }
        
        # Obtener la ruta del script actual
        $scriptPath = $PSCommandPath
        
        # Directorio de destino para la instalación
        $installDir = "$env:ProgramFiles\SoftCheck"
        if (-not (Test-Path $installDir)) {
            New-Item -Path $installDir -ItemType Directory -Force | Out-Null
        }
        
        # Copiar el script actual al directorio de instalación
        $destinationPath = "$installDir\WindowsInstallAgent.ps1"
        Copy-Item -Path $scriptPath -Destination $destinationPath -Force
        
        # Crear script de inicio para el servicio
        $serviceStarterPath = "$installDir\ServiceStarter.ps1"
        
        $serviceStarterContent = @"
# Script para iniciar el agente como servicio
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
`$ErrorActionPreference = 'Stop'

# Iniciar el agente
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File '$installDir\WindowsInstallAgent.ps1'
"@
        
        $serviceStarterContent | Set-Content -Path $serviceStarterPath -Force
        
        # Crear el servicio utilizando NSSM
        $nssmPath = "$installDir\nssm.exe"
        if (-not (Test-Path $nssmPath)) {
            # Descargar NSSM
            $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
            $nssmZipPath = "$env:TEMP\nssm.zip"
            
            # Usar WebClient para evitar bloqueos en algunos entornos
            $client = New-Object System.Net.WebClient
            $client.DownloadFile($nssmUrl, $nssmZipPath)
            
            # Extraer NSSM
            Expand-Archive -Path $nssmZipPath -DestinationPath "$env:TEMP\nssm" -Force
            Copy-Item -Path "$env:TEMP\nssm\nssm-2.24\win64\nssm.exe" -Destination $nssmPath -Force
            
            # Limpiar
            Remove-Item -Path $nssmZipPath -Force
            Remove-Item -Path "$env:TEMP\nssm" -Recurse -Force
        }
        
        # Crear el servicio con NSSM
        & $nssmPath install "SoftCheckAgent" "powershell.exe" "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$serviceStarterPath`""
        & $nssmPath set "SoftCheckAgent" DisplayName "SoftCheck Installation Monitor"
        & $nssmPath set "SoftCheckAgent" Description "Monitorea nuevas instalaciones de software y verifica su autorización"
        & $nssmPath set "SoftCheckAgent" Start "SERVICE_AUTO_START"
        
        # Iniciar el servicio
        Start-Service -Name "SoftCheckAgent"
        
        Log 1 "Servicio instalado e iniciado correctamente"
        return $true
    }
    catch {
        Log 1 "Error al instalar el servicio: $_"
        return $false
    }
}

# Desinstalar servicio
function Uninstall-Service {
    Log 1 "Desinstalando servicio..."
    
    try {
        # Detener el servicio
        Stop-Service -Name "SoftCheckAgent" -Force -ErrorAction SilentlyContinue
        
        # Dar tiempo para detenerse
        Start-Sleep -Seconds 5
        
        # Eliminar el servicio
        sc.exe delete "SoftCheckAgent" | Out-Null
        
        # Eliminar archivos de instalación
        $installDir = "$env:ProgramFiles\SoftCheck"
        if (Test-Path $installDir) {
            Remove-Item -Path $installDir -Recurse -Force
        }
        
        Log 1 "Servicio desinstalado correctamente"
        return $true
    }
    catch {
        Log 1 "Error al desinstalar el servicio: $_"
        return $false
    }
}

# Función principal
function Main {
    param (
        [string]$Command = "run"
    )
    
    # Verificar si se ejecuta como administrador
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "ADVERTENCIA: Este script debe ejecutarse como administrador para funcionar correctamente."
        
        if ($Command -eq "install" -or $Command -eq "uninstall") {
            Write-Host "ERROR: Se requieren privilegios de administrador para instalar o desinstalar el servicio."
            exit 1
        }
    }
    
    # Procesar comandos
    switch ($Command) {
        "install" {
            Install-AsService
            exit
        }
        "uninstall" {
            Uninstall-Service
            exit
        }
        "run" {
            # Iniciar el daemon de sincronización
            Start-SyncDaemon
            
            # Mostrar información inicial del agente
            Print-AgentSettings
            
            # Ejecutar el monitor de instalaciones
            Run-Monitor
        }
        default {
            Write-Host "Uso: $PSCommandPath [run|install|uninstall]"
            Write-Host "  run       - Ejecutar el agente en la consola actual"
            Write-Host "  install   - Instalar como servicio de Windows (requiere admin)"
            Write-Host "  uninstall - Desinstalar el servicio (requiere admin)"
            exit 1
        }
    }
}

# Iniciar el script con el comando de línea de comandos o "run" por defecto
Main $args[0] 