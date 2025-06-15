@echo off
echo ========================================
echo    InstallGuard Agent - Instalador
echo ========================================
echo.

REM Cambiar al directorio donde esta el script
cd /d "%~dp0"

echo Directorio actual: %CD%
echo.

REM Verificar que el ejecutable existe
if not exist "InstallGuard.Service.exe" (
    echo ERROR: No se encuentra InstallGuard.Service.exe
    echo.
    pause
    exit /b 1
)

echo OK InstallGuard.Service.exe encontrado
echo.

echo Instalando InstallGuard Agent como servicio de Windows...
echo.

REM Detener servicio existente si existe
sc query "InstallGuard Agent" >nul 2>&1
if %errorLevel% equ 0 (
    echo Deteniendo servicio existente...
    sc stop "InstallGuard Agent" >nul 2>&1
    timeout /t 3 /nobreak >nul
    echo Eliminando servicio existente...
    sc delete "InstallGuard Agent" >nul 2>&1
    timeout /t 2 /nobreak >nul
)

REM Crear directorio de instalacion
set INSTALL_DIR=C:\Program Files\InstallGuard
echo Creando directorio: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar ejecutable
echo Copiando ejecutable...
copy "InstallGuard.Service.exe" "%INSTALL_DIR%\" >nul
echo OK Ejecutable copiado

REM Crear configuracion
echo Creando configuracion...
echo {> "%INSTALL_DIR%\appsettings.json"
echo   "Logging": {>> "%INSTALL_DIR%\appsettings.json"
echo     "LogLevel": {>> "%INSTALL_DIR%\appsettings.json"
echo       "Default": "Information",>> "%INSTALL_DIR%\appsettings.json"
echo       "Microsoft.Hosting.Lifetime": "Information">> "%INSTALL_DIR%\appsettings.json"
echo     }>> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "Backend": {>> "%INSTALL_DIR%\appsettings.json"
echo     "BaseUrl": "http://localhost:4002",>> "%INSTALL_DIR%\appsettings.json"
echo     "ApiKey": "83dc386a4a636411e068f86bbe5de3bd">> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "SoftCheck": {>> "%INSTALL_DIR%\appsettings.json"
echo     "BaseUrl": "http://localhost:4002/api",>> "%INSTALL_DIR%\appsettings.json"
echo     "ApiKey": "83dc386a4a636411e068f86bbe5de3bd">> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "ApiSettings": {>> "%INSTALL_DIR%\appsettings.json"
echo     "BaseUrl": "http://localhost:4002",>> "%INSTALL_DIR%\appsettings.json"
echo     "ApiKey": "83dc386a4a636411e068f86bbe5de3bd",>> "%INSTALL_DIR%\appsettings.json"
echo     "TeamName": "myteam">> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "Features": {>> "%INSTALL_DIR%\appsettings.json"
echo     "EnableDriver": false,>> "%INSTALL_DIR%\appsettings.json"
echo     "EnableInstallationMonitoring": false,>> "%INSTALL_DIR%\appsettings.json"
echo     "PassiveMode": true,>> "%INSTALL_DIR%\appsettings.json"
echo     "SendPeriodicInventory": true,>> "%INSTALL_DIR%\appsettings.json"
echo     "InventoryIntervalMinutes": 15>> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "AgentSettings": {>> "%INSTALL_DIR%\appsettings.json"
echo     "PingIntervalMinutes": 1,>> "%INSTALL_DIR%\appsettings.json"
echo     "MonitoringIntervalSeconds": 30,>> "%INSTALL_DIR%\appsettings.json"
echo     "BatchSize": 5,>> "%INSTALL_DIR%\appsettings.json"
echo     "MaxRetries": 3>> "%INSTALL_DIR%\appsettings.json"
echo   }>> "%INSTALL_DIR%\appsettings.json"
echo }>> "%INSTALL_DIR%\appsettings.json"
echo OK Configuracion creada

REM Crear servicio
echo Creando servicio...
sc create "InstallGuard Agent" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "InstallGuard Agent" type= own
echo OK Servicio creado

REM Configurar servicio
echo Configurando servicio...
sc description "InstallGuard Agent" "Agente de monitoreo de software para SoftCheck - Modo Pasivo"
sc config "InstallGuard Agent" start= delayed-auto

REM Iniciar servicio
echo Iniciando servicio...
sc start "InstallGuard Agent"

REM Verificar estado
timeout /t 3 /nobreak >nul
echo.
echo Verificando estado del servicio...
sc query "InstallGuard Agent"

echo.
echo ========================================
echo INSTALACION COMPLETADA!
echo ========================================
echo.
echo El servicio InstallGuard Agent esta ahora ejecutandose.
echo.
pause 