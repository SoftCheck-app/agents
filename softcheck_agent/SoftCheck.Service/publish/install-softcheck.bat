@echo off
echo ========================================
echo    INSTALADOR SOFTCHECK AGENT
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

echo Instalando SoftCheck Agent...
echo.

REM Detener servicio si existe
sc query "SoftCheck Agent" >nul 2>&1
if %errorLevel% equ 0 (
    echo Deteniendo servicio existente...
    sc stop "SoftCheck Agent" >nul 2>&1
    timeout /t 3 >nul
)

REM Eliminar servicio si existe
sc query "SoftCheck Agent" >nul 2>&1
if %errorLevel% equ 0 (
    echo Eliminando servicio existente...
    sc delete "SoftCheck Agent" >nul 2>&1
    timeout /t 2 >nul
)

REM Crear servicio
echo Creando servicio SoftCheck Agent...
sc create "SoftCheck Agent" binPath= "%~dp0SoftCheck.Service.exe" start= auto DisplayName= "SoftCheck Agent"

if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear el servicio.
    pause
    exit /b 1
)

REM Configurar descripcion del servicio
sc description "SoftCheck Agent" "Agente de monitoreo de software SoftCheck para intrepit"

REM Iniciar servicio
echo Iniciando servicio...
sc start "SoftCheck Agent"

if %errorLevel% neq 0 (
    echo ERROR: No se pudo iniciar el servicio.
    pause
    exit /b 1
)

echo.
echo ========================================
echo   INSTALACION COMPLETADA EXITOSAMENTE
echo ========================================
echo.
echo El servicio SoftCheck Agent ha sido instalado y iniciado.
echo Configuracion:
echo - Team: intrepit
echo - URL: https://intrepit.softcheck.app
echo - Modo: Pasivo (inventario cada 15 minutos)
echo.
pause 