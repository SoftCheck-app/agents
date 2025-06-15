@echo off
echo ========================================
echo    InstallGuard Agent - Instalador
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

echo Instalando InstallGuard Agent como servicio de Windows...
echo.

REM Detener y eliminar servicio existente si existe
echo Verificando instalacion previa...
sc query "InstallGuard Agent" >nul 2>&1
if %errorLevel% equ 0 (
    echo Deteniendo servicio existente...
    sc stop "InstallGuard Agent" >nul 2>&1
    timeout /t 5 /nobreak >nul
    echo Eliminando servicio existente...
    sc delete "InstallGuard Agent" >nul 2>&1
    timeout /t 3 /nobreak >nul
)

REM Crear directorio de instalacion
set INSTALL_DIR=C:\Program Files\InstallGuard
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

REM Crear archivo de configuracion
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
echo     "BaseUrl": "http://localhost:4002",
echo     "ApiKey": "83dc386a4a636411e068f86bbe5de3bd"
echo   },
echo   "SoftCheck": {
echo     "BaseUrl": "http://localhost:4002/api",
echo     "ApiKey": "83dc386a4a636411e068f86bbe5de3bd"
echo   },
echo   "ApiSettings": {
echo     "BaseUrl": "http://localhost:4002",
echo     "ApiKey": "83dc386a4a636411e068f86bbe5de3bd",
echo     "TeamName": "myteam"
echo   },
echo   "Features": {
echo     "EnableDriver": false,
echo     "EnableInstallationMonitoring": false,
echo     "PassiveMode": true,
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

if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear la configuracion
    pause
    exit /b 1
)
echo OK Configuracion creada

REM Instalar como servicio
echo Instalando servicio...
sc create "InstallGuard Agent" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "InstallGuard Agent" type= own >nul

if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear el servicio
    pause
    exit /b 1
)
echo OK Servicio creado

REM Configurar servicio
echo Configurando servicio...
sc description "InstallGuard Agent" "Agente de monitoreo de software para SoftCheck - Modo Pasivo" >nul
sc failure "InstallGuard Agent" reset= 86400 actions= restart/30000/restart/60000/restart/120000 >nul
sc config "InstallGuard Agent" start= delayed-auto >nul

REM Iniciar servicio
echo Iniciando servicio...
sc start "InstallGuard Agent" >nul

REM Verificar que el servicio se inicio correctamente
timeout /t 5 /nobreak >nul
sc query "InstallGuard Agent" | find "RUNNING" >nul
if %errorLevel% equ 0 (
    echo OK Servicio iniciado correctamente
) else (
    echo ADVERTENCIA: Verificando estado del servicio...
    sc query "InstallGuard Agent"
)

echo.
echo ========================================
echo INSTALACION COMPLETADA EXITOSAMENTE!
echo ========================================
echo.
echo CONFIGURACION:
echo - Modo: PASIVO (sin interrupciones)
echo - Inventario: Cada 15 minutos
echo - Backend: http://localhost:4002
echo - Team: myteam
echo - Inicio: Automatico con Windows
echo.
echo COMANDOS UTILES:
echo - Ver estado: sc query "InstallGuard Agent"
echo - Detener: sc stop "InstallGuard Agent"
echo - Iniciar: sc start "InstallGuard Agent"
echo.
echo El servicio InstallGuard Agent esta ahora ejecutandose
echo en segundo plano y se iniciara automaticamente con Windows.
echo.
echo Presione cualquier tecla para cerrar...
pause >nul 