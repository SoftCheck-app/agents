@echo off
echo ========================================
echo  InstallGuard Agent - Desinstalador
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

echo.
echo Desinstalando InstallGuard Agent...
echo.

REM Detener servicio
echo Deteniendo servicio...
sc stop "InstallGuard Agent" >nul 2>&1

REM Esperar un momento para que se detenga completamente
timeout /t 3 /nobreak >nul

REM Eliminar servicio
echo Eliminando servicio...
sc delete "InstallGuard Agent"

REM Eliminar archivos
set INSTALL_DIR=C:\Program Files\InstallGuard
if exist "%INSTALL_DIR%" (
    echo Eliminando archivos...
    rmdir /s /q "%INSTALL_DIR%"
)

echo.
echo ========================================
echo Desinstalación completada exitosamente!
echo ========================================
echo.
echo El agente InstallGuard ha sido removido completamente del sistema.
echo.
pause 