@echo off
echo ========================================
echo   SoftCheck Agent - Intrepit - Estado
echo ========================================
echo.

REM Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ADVERTENCIA: Se recomienda ejecutar como administrador para obtener informacion completa.
    echo.
)

echo Verificando estado del servicio SoftCheck Agent - Intrepit...
echo.

REM Verificar si el servicio existe
sc query "SoftCheck Agent - Intrepit" >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: El servicio "SoftCheck Agent - Intrepit" no esta instalado.
    echo.
    echo Para instalarlo, ejecute:
    echo   install-simple.bat (desde consola)
    echo   install-final.bat (clic derecho -> Ejecutar como administrador)
    echo.
    pause
    exit /b 1
)

echo === ESTADO DEL SERVICIO ===
sc query "SoftCheck Agent - Intrepit"
echo.

echo === CONFIGURACION DEL SERVICIO ===
sc qc "SoftCheck Agent - Intrepit"
echo.

echo === PROCESOS RELACIONADOS ===
tasklist /fi "imagename eq InstallGuard.Service.exe" /fo table
echo.

echo === ARCHIVOS DE INSTALACION ===
set INSTALL_DIR=C:\Program Files\SoftCheck_Intrepit
if exist "%INSTALL_DIR%" (
    echo Directorio de instalacion: %INSTALL_DIR%
    dir "%INSTALL_DIR%" /b
    echo.
    if exist "%INSTALL_DIR%\appsettings.json" (
        echo === CONFIGURACION ACTUAL ===
        type "%INSTALL_DIR%\appsettings.json"
        echo.
    )
) else (
    echo ADVERTENCIA: Directorio de instalacion no encontrado: %INSTALL_DIR%
    echo.
)

echo === LOGS DEL SISTEMA ===
echo Para ver logs detallados, abra el Visor de Eventos y busque:
echo   Registros de Windows ^> Aplicacion ^> SoftCheck Agent - Intrepit
echo.

echo ========================================
echo Presione cualquier tecla para continuar...
pause >nul 