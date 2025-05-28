@echo off
echo ===============================================
echo    InstallGuard Service v2.0 - Instalacion
echo ===============================================
echo.

echo Verificando permisos de administrador...
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Este script requiere permisos de administrador.
    echo Por favor, ejecute como administrador.
    pause
    exit /b 1
)

echo Creando directorio de instalacion...
mkdir "C:\Program Files\InstallGuard" 2>nul

echo Copiando archivos...
copy "portable\InstallGuard.Service.exe" "C:\Program Files\InstallGuard\" >nul
copy "portable\appsettings.json" "C:\Program Files\InstallGuard\" >nul

echo Eliminando servicio anterior si existe...
sc delete "InstallGuard Service" >nul 2>&1

echo Creando servicio...
sc create "InstallGuard Service" binPath="C:\Program Files\InstallGuard\InstallGuard.Service.exe" start=auto DisplayName="InstallGuard Service v2.0"

echo Iniciando servicio...
sc start "InstallGuard Service"

echo.
echo Verificando estado del servicio...
sc query "InstallGuard Service"

echo.
echo ===============================================
echo Instalacion completada exitosamente!
echo.
echo El servicio InstallGuard v2.0 incluye:
echo - Deteccion automatica de instalaciones
echo - Analisis de seguridad en tiempo real
echo - Notificaciones popup informativas
echo - Monitoreo continuo del sistema
echo ===============================================
echo.
pause 