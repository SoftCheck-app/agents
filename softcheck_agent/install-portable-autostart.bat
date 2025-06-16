@echo off
echo ========================================
echo InstallGuard v3.0 - Instalacion Portable
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

REM Detener proceso si existe
echo [INFO] Deteniendo procesos existentes...
taskkill /F /IM "InstallGuard.Service.exe" >nul 2>&1
timeout /t 2 >nul

REM Crear directorio de instalacion
set INSTALL_DIR=C:\InstallGuard
echo [INFO] Creando directorio de instalacion: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM Copiar archivos
echo [INFO] Copiando archivos del agente...
copy /Y "portable_v3_final\InstallGuard.Service.exe" "%INSTALL_DIR%\" >nul
copy /Y "portable_v3_final\appsettings.json" "%INSTALL_DIR%\" >nul

if not exist "%INSTALL_DIR%\InstallGuard.Service.exe" (
    echo ERROR: No se pudo copiar el ejecutable principal.
    pause
    exit /b 1
)

echo [INFO] Archivos copiados correctamente.

REM Crear script de inicio
echo [INFO] Creando script de auto-inicio...
echo @echo off > "%INSTALL_DIR%\start-agent.bat"
echo cd /d "%INSTALL_DIR%" >> "%INSTALL_DIR%\start-agent.bat"
echo start "" "%INSTALL_DIR%\InstallGuard.Service.exe" >> "%INSTALL_DIR%\start-agent.bat"

REM Agregar al registro para auto-inicio (HKLM para todos los usuarios)
echo [INFO] Configurando auto-inicio en el sistema...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "InstallGuard" /t REG_SZ /d "\"%INSTALL_DIR%\InstallGuard.Service.exe\"" /f >nul

if %errorLevel% neq 0 (
    echo WARNING: No se pudo configurar el auto-inicio automatico.
    echo Puedes configurarlo manualmente en msconfig.exe
) else (
    echo [INFO] Auto-inicio configurado correctamente.
)

REM Crear acceso directo en el escritorio (opcional)
echo [INFO] Creando acceso directo en el escritorio...
powershell -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%PUBLIC%\Desktop\InstallGuard.lnk'); $Shortcut.TargetPath = '%INSTALL_DIR%\InstallGuard.Service.exe'; $Shortcut.WorkingDirectory = '%INSTALL_DIR%'; $Shortcut.Description = 'InstallGuard Security Agent'; $Shortcut.Save()" >nul 2>&1

REM Iniciar el agente
echo [INFO] Iniciando InstallGuard...
start "" "%INSTALL_DIR%\InstallGuard.Service.exe"

echo.
echo ========================================
echo INSTALACION COMPLETADA
echo ========================================
echo.
echo InstallGuard v3.0 se ha instalado correctamente en modo portable.
echo.
echo UBICACION: %INSTALL_DIR%
echo AUTO-INICIO: Configurado (se ejecutara al iniciar Windows)
echo.
echo CARACTERISTICAS:
echo - Deteccion automatica de instalaciones
echo - Analisis de seguridad en tiempo real
echo - Notificaciones popup informativas
echo - Reporte automatico a webapp SaaS
echo - Ejecucion en segundo plano
echo.
echo Para desinstalar: ejecuta uninstall-portable.bat
echo Para verificar estado: busca el proceso InstallGuard.Service.exe
echo.
echo Presiona cualquier tecla para continuar...
pause >nul 