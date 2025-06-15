@echo off
echo ========================================
echo    SoftCheck Agent - Intrepit v1.0.5
echo ========================================
echo.

REM Cambiar al directorio donde esta el script
cd /d "%~dp0"

REM Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Este script requiere permisos de administrador.
    echo Por favor, ejecute como administrador.
    echo.
    pause
    exit /b 1
)

echo Permisos de administrador confirmados.
echo.

REM Verificar que el ejecutable existe
if not exist "%~dp0InstallGuard.Service.exe" (
    echo ERROR: No se encuentra InstallGuard.Service.exe
    echo Directorio actual: %CD%
    echo Directorio del script: %~dp0
    echo.
    echo Archivos .exe encontrados:
    dir "%~dp0*.exe" /b 2>nul
    if errorlevel 1 echo   (Ningun archivo .exe encontrado)
    echo.
    pause
    exit /b 1
)

echo Verificando ejecutable...
echo OK InstallGuard.Service.exe encontrado
for %%I in ("%~dp0InstallGuard.Service.exe") do echo   Tamano: %%~zI bytes
echo.

echo Instalando SoftCheck Agent - Intrepit como servicio de Windows...
echo.

REM Detener y eliminar servicio existente si existe
echo Verificando instalacion previa...
sc query "SoftCheck Agent - Intrepit" >nul 2>&1
if %errorLevel% equ 0 (
    echo Deteniendo servicio existente...
    sc stop "SoftCheck Agent - Intrepit" >nul 2>&1
    timeout /t 5 /nobreak >nul
    echo Eliminando servicio existente...
    sc delete "SoftCheck Agent - Intrepit" >nul 2>&1
    timeout /t 3 /nobreak >nul
)

REM Crear directorio de instalacion
set INSTALL_DIR=C:\Program Files\SoftCheck_Intrepit
echo Creando directorio: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar ejecutable
echo Copiando archivos...
copy "%~dp0InstallGuard.Service.exe" "%INSTALL_DIR%\" >nul
if %errorLevel% neq 0 (
    echo ERROR: No se pudo copiar el ejecutable
    pause
    exit /b 1
)
echo OK Ejecutable copiado

REM Copiar archivos adicionales si existen
if exist "%~dp0InstallGuard.Service.pdb" copy "%~dp0InstallGuard.Service.pdb" "%INSTALL_DIR%\" >nul
if exist "%~dp0InstallGuard.Common.pdb" copy "%~dp0InstallGuard.Common.pdb" "%INSTALL_DIR%\" >nul

REM Crear archivo de configuracion con auto-actualizacion para Intrepit
echo Creando configuracion...
(
echo {
echo   "Logging": {
echo     "LogLevel": {
echo       "Default": "Information",
echo       "Microsoft.Hosting.Lifetime": "Information"
echo     }
echo   },
echo   "Backend": {
echo     "BaseUrl": "https://intrepit.softcheck.app",
echo     "ApiKey": "89888ecba1b4a5a26716e80a396fd5db"
echo   },
echo   "SoftCheck": {
echo     "BaseUrl": "https://intrepit.softcheck.app/api",
echo     "ApiKey": "89888ecba1b4a5a26716e80a396fd5db"
echo   },
echo   "ApiSettings": {
echo     "BaseUrl": "https://intrepit.softcheck.app",
echo     "ApiKey": "89888ecba1b4a5a26716e80a396fd5db",
echo     "TeamName": "intrepit"
echo   },
echo   "Features": {
echo     "EnableDriver": false,
echo     "EnableInstallationMonitoring": false,
echo     "PassiveMode": true,
echo     "SendPeriodicInventory": true,
echo     "InventoryIntervalMinutes": 15,
echo     "EnableAutoUpdate": true
echo   },
echo   "AgentSettings": {
echo     "PingIntervalMinutes": 1,
echo     "MonitoringIntervalSeconds": 30,
echo     "BatchSize": 5,
echo     "MaxRetries": 3
echo   },
echo   "AutoUpdate": {
echo     "CheckIntervalMinutes": 30,
echo     "UpdateCheckUrl": "https://agents.softcheck.app/windows-agent/latest-version",
echo     "Enabled": true
echo   }
echo }
) > "%INSTALL_DIR%\appsettings.json"

if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear la configuracion
    pause
    exit /b 1
)
echo OK Configuracion creada

REM Instalar como servicio
echo Instalando servicio...
sc create "SoftCheck Agent - Intrepit" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "SoftCheck Agent - Intrepit" type= own >nul

if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear el servicio
    pause
    exit /b 1
)
echo OK Servicio creado

REM Configurar servicio
echo Configurando servicio...
sc description "SoftCheck Agent - Intrepit" "Agente de monitoreo de software para SoftCheck Intrepit - Modo Pasivo con Auto-actualizacion" >nul
sc failure "SoftCheck Agent - Intrepit" reset= 86400 actions= restart/30000/restart/60000/restart/120000 >nul
sc config "SoftCheck Agent - Intrepit" start= delayed-auto >nul

REM Iniciar servicio
echo Iniciando servicio...
sc start "SoftCheck Agent - Intrepit" >nul

REM Verificar que el servicio se inicio correctamente
timeout /t 5 /nobreak >nul
sc query "SoftCheck Agent - Intrepit" | find "RUNNING" >nul
if %errorLevel% equ 0 (
    echo OK Servicio iniciado correctamente
) else (
    echo ADVERTENCIA: Verificando estado del servicio...
    sc query "SoftCheck Agent - Intrepit"
)

echo.
echo ========================================
echo INSTALACION COMPLETADA EXITOSAMENTE!
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
echo - Inicio: Automatico con Windows
echo.
echo COMANDOS UTILES:
echo - Ver estado: sc query "SoftCheck Agent - Intrepit"
echo - Detener: sc stop "SoftCheck Agent - Intrepit"
echo - Iniciar: sc start "SoftCheck Agent - Intrepit"
echo.
echo El servicio SoftCheck Agent - Intrepit esta ahora ejecutandose
echo en segundo plano y se iniciara automaticamente con Windows.
echo.
echo NUEVA FUNCIONALIDAD:
echo El agente verificara automaticamente cada 30 minutos si hay
echo nuevas versiones disponibles y se actualizara automaticamente.
echo.
echo Presione cualquier tecla para cerrar...
pause >nul 