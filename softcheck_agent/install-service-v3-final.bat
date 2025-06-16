@echo off
echo ========================================
echo InstallGuard v3.0 FINAL - Instalacion
echo ========================================
echo.

REM Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Este script requiere permisos de administrador.
    echo Por favor, ejecuta como administrador.
    pause
    exit /b 1
)

echo [INFO] Verificando permisos de administrador... OK
echo.

REM Detener servicio si existe
echo [INFO] Deteniendo servicio existente...
sc stop "InstallGuard" >nul 2>&1
timeout /t 3 >nul

REM Eliminar servicio si existe
echo [INFO] Eliminando servicio existente...
sc delete "InstallGuard" >nul 2>&1
timeout /t 2 >nul

REM Crear directorio de instalacion
set INSTALL_DIR=C:\Program Files\InstallGuard
echo [INFO] Creando directorio de instalacion: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar archivos
echo [INFO] Copiando archivos del agente...
copy /Y "portable_v3_final\InstallGuard.Service.exe" "%INSTALL_DIR%\" >nul
copy /Y "portable_v3_final\appsettings.json" "%INSTALL_DIR%\" >nul

if not exist "%INSTALL_DIR%\InstallGuard.Service.exe" (
    echo ERROR: No se pudo copiar el ejecutable principal.
    pause
    exit /b 1
)

echo [INFO] Archivos copiados correctamente.

REM Crear servicio
echo [INFO] Instalando servicio de Windows...
sc create "InstallGuard" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "InstallGuard Security Agent v3.0"

if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear el servicio.
    pause
    exit /b 1
)

REM Configurar descripcion del servicio
sc description "InstallGuard" "Agente de seguridad que monitorea instalaciones de software y reporta a la webapp SaaS"

REM Iniciar servicio
echo [INFO] Iniciando servicio...
sc start "InstallGuard"

if %errorLevel% neq 0 (
    echo WARNING: El servicio se instalo pero no se pudo iniciar automaticamente.
    echo Puedes iniciarlo manualmente desde services.msc
) else (
    echo [INFO] Servicio iniciado correctamente.
)

echo.
echo ========================================
echo INSTALACION COMPLETADA
echo ========================================
echo.
echo InstallGuard v3.0 FINAL se ha instalado correctamente.
echo.
echo CARACTERISTICAS:
echo - Deteccion automatica de instalaciones
echo - Analisis de seguridad en tiempo real
echo - Notificaciones popup informativas
echo - Reporte automatico a webapp SaaS
echo - SIN datos de prueba (solo datos reales)
echo.
echo El servicio se ejecuta automaticamente en segundo plano.
echo Para verificar el estado: services.msc
echo Para ver logs: Event Viewer ^> Windows Logs ^> Application
echo.
echo Presiona cualquier tecla para continuar...
pause >nul 