@echo off
echo ========================================
echo   DESINSTALADOR SOFTCHECK AGENT
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

echo Desinstalando SoftCheck Agent...
echo.

REM Detener servicio
sc query "SoftCheck Agent" >nul 2>&1
if %errorLevel% equ 0 (
    echo Deteniendo servicio...
    sc stop "SoftCheck Agent" >nul 2>&1
    timeout /t 5 >nul
    
    REM Eliminar servicio
    echo Eliminando servicio...
    sc delete "SoftCheck Agent" >nul 2>&1
    
    if %errorLevel% equ 0 (
        echo Servicio eliminado exitosamente.
    ) else (
        echo ERROR: No se pudo eliminar el servicio.
    )
) else (
    echo El servicio SoftCheck Agent no esta instalado.
)

echo.
echo ========================================
echo   DESINSTALACION COMPLETADA
echo ========================================
echo.
pause 