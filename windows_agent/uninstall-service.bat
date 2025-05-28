@echo off
echo ===============================================
echo   InstallGuard Service v2.0 - Desinstalacion
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

echo Deteniendo servicio...
sc stop "InstallGuard Service" >nul 2>&1

echo Eliminando servicio...
sc delete "InstallGuard Service"

echo Eliminando archivos...
rmdir /s /q "C:\Program Files\InstallGuard" 2>nul

echo.
echo ===============================================
echo Desinstalacion completada exitosamente!
echo ===============================================
echo.
pause 