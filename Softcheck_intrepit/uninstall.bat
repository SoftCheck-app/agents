@echo off
echo ========================================
echo  SoftCheck Agent - Intrepit - Desinstalar
echo ========================================
echo.

REM Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Este script requiere permisos de administrador.
    echo Por favor, ejecute como administrador.
    echo.
    pause
    exit /b 1
)

echo ADVERTENCIA: Esto desinstalara completamente SoftCheck Agent - Intrepit
echo.
set /p confirm=¿Esta seguro? (S/N): 
if /i not "%confirm%"=="S" (
    echo Operacion cancelada.
    pause
    exit /b 0
)

echo.
echo Desinstalando SoftCheck Agent - Intrepit...
echo.

REM Detener servicio
echo Deteniendo servicio...
sc stop "SoftCheck Agent - Intrepit" >nul 2>&1
timeout /t 5 /nobreak >nul

REM Eliminar servicio
echo Eliminando servicio...
sc delete "SoftCheck Agent - Intrepit" >nul 2>&1

REM Eliminar archivos
set INSTALL_DIR=C:\Program Files\SoftCheck_Intrepit
if exist "%INSTALL_DIR%" (
    echo Eliminando archivos de %INSTALL_DIR%...
    rd /s /q "%INSTALL_DIR%" >nul 2>&1
    if exist "%INSTALL_DIR%" (
        echo ADVERTENCIA: No se pudieron eliminar todos los archivos
        echo Directorio: %INSTALL_DIR%
    ) else (
        echo OK Archivos eliminados
    )
) else (
    echo Directorio de instalacion no encontrado
)

echo.
echo ========================================
echo DESINSTALACION COMPLETADA
echo ========================================
echo.
echo SoftCheck Agent - Intrepit ha sido desinstalado del sistema.
echo.
pause 