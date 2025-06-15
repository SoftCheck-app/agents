@echo off
echo ========================================
echo    SoftCheck Agent - Intrepit v1.0.5
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

echo Instalando SoftCheck Agent - Intrepit como servicio de Windows...
echo.

REM Detener servicio existente si existe
sc query "SoftCheck Agent - Intrepit" >nul 2>&1
if %errorLevel% equ 0 (
    echo Deteniendo servicio existente...
    sc stop "SoftCheck Agent - Intrepit" >nul 2>&1
    timeout /t 3 /nobreak >nul
    echo Eliminando servicio existente...
    sc delete "SoftCheck Agent - Intrepit" >nul 2>&1
    timeout /t 2 /nobreak >nul
)

REM Crear directorio de instalacion
set INSTALL_DIR=C:\Program Files\SoftCheck_Intrepit
echo Creando directorio: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar ejecutable
echo Copiando ejecutable...
copy "InstallGuard.Service.exe" "%INSTALL_DIR%\" >nul
echo OK Ejecutable copiado

REM Crear configuracion con auto-actualizacion para Intrepit
echo Creando configuracion...
echo {> "%INSTALL_DIR%\appsettings.json"
echo   "Logging": {>> "%INSTALL_DIR%\appsettings.json"
echo     "LogLevel": {>> "%INSTALL_DIR%\appsettings.json"
echo       "Default": "Information",>> "%INSTALL_DIR%\appsettings.json"
echo       "Microsoft.Hosting.Lifetime": "Information">> "%INSTALL_DIR%\appsettings.json"
echo     }>> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "Backend": {>> "%INSTALL_DIR%\appsettings.json"
echo     "BaseUrl": "https://intrepit.softcheck.app",>> "%INSTALL_DIR%\appsettings.json"
echo     "ApiKey": "89888ecba1b4a5a26716e80a396fd5db">> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "SoftCheck": {>> "%INSTALL_DIR%\appsettings.json"
echo     "BaseUrl": "https://intrepit.softcheck.app/api",>> "%INSTALL_DIR%\appsettings.json"
echo     "ApiKey": "89888ecba1b4a5a26716e80a396fd5db">> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "ApiSettings": {>> "%INSTALL_DIR%\appsettings.json"
echo     "BaseUrl": "https://intrepit.softcheck.app",>> "%INSTALL_DIR%\appsettings.json"
echo     "ApiKey": "89888ecba1b4a5a26716e80a396fd5db",>> "%INSTALL_DIR%\appsettings.json"
echo     "TeamName": "intrepit">> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "Features": {>> "%INSTALL_DIR%\appsettings.json"
echo     "EnableDriver": false,>> "%INSTALL_DIR%\appsettings.json"
echo     "EnableInstallationMonitoring": false,>> "%INSTALL_DIR%\appsettings.json"
echo     "PassiveMode": true,>> "%INSTALL_DIR%\appsettings.json"
echo     "SendPeriodicInventory": true,>> "%INSTALL_DIR%\appsettings.json"
echo     "InventoryIntervalMinutes": 15,>> "%INSTALL_DIR%\appsettings.json"
echo     "EnableAutoUpdate": true>> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "AgentSettings": {>> "%INSTALL_DIR%\appsettings.json"
echo     "PingIntervalMinutes": 1,>> "%INSTALL_DIR%\appsettings.json"
echo     "MonitoringIntervalSeconds": 30,>> "%INSTALL_DIR%\appsettings.json"
echo     "BatchSize": 5,>> "%INSTALL_DIR%\appsettings.json"
echo     "MaxRetries": 3>> "%INSTALL_DIR%\appsettings.json"
echo   },>> "%INSTALL_DIR%\appsettings.json"
echo   "AutoUpdate": {>> "%INSTALL_DIR%\appsettings.json"
echo     "CheckIntervalMinutes": 30,>> "%INSTALL_DIR%\appsettings.json"
echo     "UpdateCheckUrl": "https://agents.softcheck.app/windows-agent/latest-version",>> "%INSTALL_DIR%\appsettings.json"
echo     "Enabled": true>> "%INSTALL_DIR%\appsettings.json"
echo   }>> "%INSTALL_DIR%\appsettings.json"
echo }>> "%INSTALL_DIR%\appsettings.json"
echo OK Configuracion creada

REM Crear servicio
echo Creando servicio...
sc create "SoftCheck Agent - Intrepit" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "SoftCheck Agent - Intrepit" type= own
echo OK Servicio creado

REM Configurar servicio
echo Configurando servicio...
sc description "SoftCheck Agent - Intrepit" "Agente de monitoreo de software para SoftCheck Intrepit - Modo Pasivo con Auto-actualizacion"
sc config "SoftCheck Agent - Intrepit" start= delayed-auto

REM Iniciar servicio
echo Iniciando servicio...
sc start "SoftCheck Agent - Intrepit"

REM Verificar estado
timeout /t 3 /nobreak >nul
echo.
echo Verificando estado del servicio...
sc query "SoftCheck Agent - Intrepit"

echo.
echo ========================================
echo INSTALACION COMPLETADA!
echo ========================================
echo.
echo CONFIGURACION INTREPIT:
echo - Version: 1.0.5
echo - Cliente: Intrepit
echo - Modo: PASIVO (sin interrupciones)
echo - Inventario: Cada 15 minutos
echo - Auto-actualizacion: ACTIVADA (cada 30 minutos)
echo - Backend: https://intrepit.softcheck.app
echo - Team: intrepit
echo.
echo El servicio SoftCheck Agent - Intrepit esta ahora ejecutandose
echo y se actualizara automaticamente cuando haya nuevas versiones.
echo.
pause 