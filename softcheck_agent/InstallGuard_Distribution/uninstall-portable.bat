@echo off
echo ========================================
echo InstallGuard v3.0 - Desinstalacion
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

set INSTALL_DIR=C:\InstallGuard

REM Detener proceso si existe
echo [INFO] Deteniendo InstallGuard...
taskkill /F /IM "InstallGuard.Service.exe" >nul 2>&1
timeout /t 3 >nul

REM Eliminar del auto-inicio
echo [INFO] Eliminando auto-inicio...
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "InstallGuard" /f >nul 2>&1

REM Eliminar acceso directo del escritorio
echo [INFO] Eliminando acceso directo...
del "%PUBLIC%\Desktop\InstallGuard.lnk" >nul 2>&1

REM Eliminar archivos
echo [INFO] Eliminando archivos...
if exist "%INSTALL_DIR%" (
    rmdir /S /Q "%INSTALL_DIR%" >nul 2>&1
    if exist "%INSTALL_DIR%" (
        echo WARNING: No se pudieron eliminar todos los archivos.
        echo Elimina manualmente la carpeta: %INSTALL_DIR%
    ) else (
        echo [INFO] Archivos eliminados correctamente.
    )
) else (
    echo [INFO] No se encontraron archivos para eliminar.
)

echo.
echo ========================================
echo DESINSTALACION COMPLETADA
echo ========================================
echo.
echo InstallGuard ha sido desinstalado del sistema.
echo.
echo Presiona cualquier tecla para continuar...
pause >nul