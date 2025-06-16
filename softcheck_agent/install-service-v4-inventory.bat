@echo off
setlocal enabledelayedexpansion

echo ========================================
echo InstallGuard v4.0 - Inventario Completo
echo ========================================
echo.

REM Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Este script requiere permisos de administrador.
    echo Por favor, ejecute como administrador.
    pause
    exit /b 1
)

echo [INFO] Verificando permisos de administrador... OK
echo.

REM Definir rutas
set "SOURCE_DIR=%~dp0portable_v4_inventory"
set "INSTALL_DIR=C:\Program Files\InstallGuard"
set "SERVICE_NAME=InstallGuard"
set "SERVICE_DISPLAY_NAME=InstallGuard Security Monitor v4.0"
set "SERVICE_DESCRIPTION=Monitorea instalaciones de software y envía inventario completo a webapp SaaS"

echo [INFO] Configuración:
echo   - Directorio fuente: %SOURCE_DIR%
echo   - Directorio destino: %INSTALL_DIR%
echo   - Nombre del servicio: %SERVICE_NAME%
echo.

REM Verificar que existe el directorio fuente
if not exist "%SOURCE_DIR%" (
    echo ERROR: No se encuentra el directorio %SOURCE_DIR%
    echo Asegúrese de que el proyecto esté compilado.
    pause
    exit /b 1
)

echo [INFO] Verificando archivos fuente... OK
echo.

REM Detener el servicio si existe
echo [INFO] Verificando servicio existente...
sc query "%SERVICE_NAME%" >nul 2>&1
if %errorLevel% equ 0 (
    echo [INFO] Deteniendo servicio existente...
    sc stop "%SERVICE_NAME%" >nul 2>&1
    timeout /t 3 /nobreak >nul
    
    echo [INFO] Eliminando servicio existente...
    sc delete "%SERVICE_NAME%" >nul 2>&1
    timeout /t 2 /nobreak >nul
)

REM Crear directorio de instalación
echo [INFO] Creando directorio de instalación...
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
)

REM Copiar archivos
echo [INFO] Copiando archivos de InstallGuard v4.0...
xcopy "%SOURCE_DIR%\*" "%INSTALL_DIR%\" /Y /Q >nul
if %errorLevel% neq 0 (
    echo ERROR: No se pudieron copiar los archivos.
    pause
    exit /b 1
)

echo [INFO] Archivos copiados exitosamente.
echo.

REM Verificar que el ejecutable existe
if not exist "%INSTALL_DIR%\InstallGuard.Service.exe" (
    echo ERROR: No se encuentra InstallGuard.Service.exe en %INSTALL_DIR%
    pause
    exit /b 1
)

REM Crear el servicio
echo [INFO] Instalando servicio de Windows...
sc create "%SERVICE_NAME%" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" DisplayName= "%SERVICE_DISPLAY_NAME%" start= auto
if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear el servicio.
    pause
    exit /b 1
)

REM Configurar descripción del servicio
sc description "%SERVICE_NAME%" "%SERVICE_DESCRIPTION%"

REM Configurar recuperación del servicio en caso de fallo
echo [INFO] Configurando recuperación automática del servicio...
sc failure "%SERVICE_NAME%" reset= 86400 actions= restart/5000/restart/10000/restart/30000

REM Iniciar el servicio
echo [INFO] Iniciando servicio InstallGuard v4.0...
sc start "%SERVICE_NAME%"
if %errorLevel% neq 0 (
    echo WARNING: El servicio se instaló pero no se pudo iniciar automáticamente.
    echo Puede iniciarlo manualmente desde services.msc
) else (
    echo [INFO] Servicio iniciado exitosamente.
)

echo.
echo ========================================
echo INSTALACIÓN COMPLETADA
echo ========================================
echo.
echo InstallGuard v4.0 ha sido instalado exitosamente.
echo.
echo NUEVA FUNCIONALIDAD v4.0:
echo - Envía inventario COMPLETO cada 30 segundos
echo - Todas las aplicaciones instaladas se sincronizan
echo - Envío optimizado en lotes de 5 aplicaciones
echo - Redundancia total para no perder aplicaciones
echo.
echo Ubicación: %INSTALL_DIR%
echo Servicio: %SERVICE_NAME%
echo Estado: Ejecutándose automáticamente
echo.
echo VERIFICACIÓN:
echo 1. Abra services.msc y verifique que "InstallGuard Security Monitor v4.0" esté ejecutándose
echo 2. Revise los logs en: %INSTALL_DIR%\logs\
echo 3. Busque mensajes: "Enviando inventario completo de aplicaciones a webapp"
echo 4. Confirme en la webapp que se reciben datos cada 30 segundos
echo.
echo Para desinstalar: ejecute uninstall-service.bat como administrador
echo.
pause 