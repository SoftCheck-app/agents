@echo off
echo ========================================
echo   InstallGuard Agent - Estado
echo ========================================
echo.

REM Verificar si el servicio existe
sc query "InstallGuard Agent" >nul 2>&1
if %errorLevel% == 0 (
    echo SERVICIO ENCONTRADO:
    echo.
    sc query "InstallGuard Agent"
    echo.
    
    REM Verificar configuración del servicio
    echo CONFIGURACION DEL SERVICIO:
    sc qc "InstallGuard Agent"
    echo.
    
    REM Verificar archivos de instalación
    set INSTALL_DIR=C:\Program Files\InstallGuard
    if exist "%INSTALL_DIR%\InstallGuard.Service.exe" (
        echo ARCHIVOS: Instalación encontrada en %INSTALL_DIR%
        dir "%INSTALL_DIR%" /b
    ) else (
        echo ARCHIVOS: ERROR - No se encuentran archivos de instalación
    )
    
    echo.
    echo COMANDOS DISPONIBLES:
    echo - Iniciar: sc start "InstallGuard Agent"
    echo - Detener: sc stop "InstallGuard Agent"
    echo - Reiniciar: sc stop "InstallGuard Agent" ^&^& timeout /t 3 ^&^& sc start "InstallGuard Agent"
    echo - Ver logs: eventvwr.msc
    
) else (
    echo SERVICIO NO ENCONTRADO
    echo.
    echo El servicio InstallGuard Agent no está instalado.
    echo Ejecute install.bat para instalarlo.
)

echo.
pause 