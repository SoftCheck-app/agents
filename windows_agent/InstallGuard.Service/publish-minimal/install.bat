@echo off
echo ========================================
echo    InstallGuard Agent - Instalador
echo ========================================
echo.

REM Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Permisos de administrador confirmados.
) else (
    echo ERROR: Este script requiere permisos de administrador.
    echo Por favor, ejecute como administrador.
    pause
    exit /b 1
)

REM Verificar que el ejecutable existe
if not exist "InstallGuard.Service.exe" (
    echo ERROR: No se encuentra InstallGuard.Service.exe
    echo Asegurese de que este script este en la misma carpeta que el ejecutable.
    pause
    exit /b 1
)

echo.
echo Instalando InstallGuard Agent como servicio de Windows...
echo.

REM Crear directorio de instalación
set INSTALL_DIR=C:\Program Files\InstallGuard
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar ejecutable
echo Copiando archivos...
copy "InstallGuard.Service.exe" "%INSTALL_DIR%\"

REM Crear archivo de configuración
echo Creando configuracion...
(
echo {
echo   "Logging": {
echo     "LogLevel": {
echo       "Default": "Information",
echo       "Microsoft.Hosting.Lifetime": "Information"
echo     }
echo   },
echo   "ApiSettings": {
echo     "BaseUrl": "https://softcheck-v3.onrender.com",
echo     "ApiKey": "c07f7b249e2b4b970a04f97b169db6a5",
echo     "TeamName": "myteam"
echo   },
echo   "Features": {
echo     "PassiveMode": true,
echo     "EnableInstallationMonitoring": false,
echo     "EnableNotifications": false,
echo     "SendPeriodicInventory": true,
echo     "InventoryIntervalMinutes": 15
echo   },
echo   "AgentSettings": {
echo     "PingIntervalMinutes": 1,
echo     "MonitoringIntervalSeconds": 30,
echo     "BatchSize": 5,
echo     "MaxRetries": 3
echo   }
echo }
) > "%INSTALL_DIR%\appsettings.json"

REM Instalar como servicio
echo Instalando servicio...
sc create "InstallGuard Agent" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "InstallGuard Agent"

REM Configurar descripción del servicio
sc description "InstallGuard Agent" "Agente de monitoreo de software para SoftCheck"

REM Configurar recuperación del servicio en caso de fallo
sc failure "InstallGuard Agent" reset= 86400 actions= restart/60000/restart/60000/restart/60000

REM Iniciar servicio
echo Iniciando servicio...
sc start "InstallGuard Agent"

echo.
echo ========================================
echo Instalación completada exitosamente!
echo ========================================
echo.
echo El agente InstallGuard se ha instalado como servicio de Windows
echo y se iniciará automáticamente con el sistema.
echo.
echo CONFIGURACION:
echo - Modo: PASIVO (sin interrupciones)
echo - Inventario: Cada 15 minutos
echo - Ping: Cada minuto
echo - Backend: https://softcheck-v3.onrender.com
echo - Team: myteam
echo.
echo COMANDOS UTILES:
echo - Ver estado: sc query "InstallGuard Agent"
echo - Detener: sc stop "InstallGuard Agent"
echo - Iniciar: sc start "InstallGuard Agent"
echo - Desinstalar: sc stop "InstallGuard Agent" ^&^& sc delete "InstallGuard Agent" ^&^& rmdir /s /q "%INSTALL_DIR%"
echo.
echo Para ver logs: Visor de eventos ^> Registros de Windows ^> Sistema
echo.
pause 