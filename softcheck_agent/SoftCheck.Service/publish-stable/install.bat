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

REM Mostrar información de diagnóstico
echo.
echo DIAGNOSTICO:
echo Directorio actual: %CD%
echo Archivos en directorio actual:
dir /b *.exe 2>nul
echo.

REM Verificar que el ejecutable existe con múltiples métodos
echo Verificando ejecutable...
if exist "InstallGuard.Service.exe" (
    echo ✓ InstallGuard.Service.exe encontrado
    for %%I in ("InstallGuard.Service.exe") do echo   Tamaño: %%~zI bytes
) else (
    echo ❌ ERROR: No se encuentra InstallGuard.Service.exe
    echo.
    echo SOLUCION:
    echo 1. Asegurese de que este script este en la misma carpeta que InstallGuard.Service.exe
    echo 2. Verifique que el archivo no este bloqueado por Windows
    echo 3. Intente extraer nuevamente el ZIP completo
    echo.
    echo Archivos .exe encontrados en esta carpeta:
    dir *.exe /b 2>nul
    if errorlevel 1 echo   (Ningún archivo .exe encontrado)
    echo.
    pause
    exit /b 1
)

echo.
echo Instalando InstallGuard Agent como servicio de Windows...
echo.

REM Detener y eliminar servicio existente si existe
echo Verificando instalación previa...
sc query "InstallGuard Agent" >nul 2>&1
if %errorLevel% == 0 (
    echo Deteniendo servicio existente...
    sc stop "InstallGuard Agent" >nul 2>&1
    timeout /t 5 /nobreak >nul
    echo Eliminando servicio existente...
    sc delete "InstallGuard Agent" >nul 2>&1
    timeout /t 3 /nobreak >nul
)

REM Crear directorio de instalación
set INSTALL_DIR=C:\Program Files\InstallGuard
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar todos los archivos necesarios
echo Copiando archivos...
copy "InstallGuard.Service.exe" "%INSTALL_DIR%\" >nul
if exist "InstallGuard.Service.pdb" copy "InstallGuard.Service.pdb" "%INSTALL_DIR%\" >nul
if exist "InstallGuard.Common.pdb" copy "InstallGuard.Common.pdb" "%INSTALL_DIR%\" >nul

REM Crear archivo de configuración actualizado
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

REM Instalar como servicio con configuración mejorada
echo Instalando servicio...
sc create "InstallGuard Agent" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "InstallGuard Agent" type= own

REM Configurar descripción del servicio
sc description "InstallGuard Agent" "Agente de monitoreo de software para SoftCheck - Modo Pasivo"

REM Configurar recuperación del servicio en caso de fallo (reiniciar automáticamente)
sc failure "InstallGuard Agent" reset= 86400 actions= restart/30000/restart/60000/restart/120000

REM Configurar el servicio para que se ejecute con retraso después del inicio del sistema
sc config "InstallGuard Agent" start= delayed-auto

REM Iniciar servicio
echo Iniciando servicio...
sc start "InstallGuard Agent"

REM Verificar que el servicio se inició correctamente
timeout /t 3 /nobreak >nul
sc query "InstallGuard Agent" | find "RUNNING" >nul
if %errorLevel% == 0 (
    echo Servicio iniciado correctamente.
) else (
    echo ADVERTENCIA: El servicio puede no haberse iniciado correctamente.
    echo Verifique los logs en el Visor de Eventos.
)

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
echo - Backend: http://localhost:4002
echo - Team: myteam
echo - Inicio: AUTOMATICO CON RETRASO
echo.
echo COMANDOS UTILES:
echo - Ver estado: sc query "InstallGuard Agent"
echo - Detener: sc stop "InstallGuard Agent"
echo - Iniciar: sc start "InstallGuard Agent"
echo - Reiniciar: sc stop "InstallGuard Agent" ^&^& timeout /t 3 ^&^& sc start "InstallGuard Agent"
echo - Desinstalar: Ejecutar uninstall.bat
echo.
echo LOGS:
echo - Visor de eventos ^> Registros de Windows ^> Sistema
echo - Visor de eventos ^> Registros de aplicaciones y servicios ^> InstallGuard Service
echo.
echo NOTA: El servicio se ejecutará en segundo plano incluso después de
echo cerrar esta ventana y se iniciará automáticamente al reiniciar Windows.
echo.
pause 