@echo off
echo ========================================
echo    InstallGuard Agent - Instalador
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
echo Instalando InstallGuard Agent como servicio de Windows...
echo.

REM Crear directorio de instalación
set INSTALL_DIR=C:\Program Files\InstallGuard
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar archivos
echo Copiando archivos...
copy "InstallGuard.Service.exe" "%INSTALL_DIR%\"
copy "appsettings.json" "%INSTALL_DIR%\"
copy "*.pdb" "%INSTALL_DIR%\" >nul 2>&1

REM Instalar como servicio
echo Instalando servicio...
sc create "InstallGuard Agent" binPath= "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" start= auto DisplayName= "InstallGuard Agent"

REM Configurar descripción del servicio
sc description "InstallGuard Agent" "Agente de monitoreo de software para SoftCheck"

REM Iniciar servicio
echo Iniciando servicio...
sc start "InstallGuard Agent"

echo.
echo ========================================
echo Instalación completada exitosamente!
echo ========================================
echo.
echo El agente InstallGuard se ha instalado como servicio de Windows
echo y se iniciará automáticamente con el sistema.
echo.
echo Para verificar el estado: sc query "InstallGuard Agent"
echo Para detener: sc stop "InstallGuard Agent"
echo Para desinstalar: sc delete "InstallGuard Agent"
echo.
pause 