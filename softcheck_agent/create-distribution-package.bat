@echo off
echo ========================================
echo Creando Paquete de Distribucion
echo InstallGuard v3.0 FINAL
echo ========================================
echo.

set DIST_DIR=InstallGuard_Distribution
set DATE_STAMP=%date:~6,4%-%date:~3,2%-%date:~0,2%

REM Crear directorio de distribución
echo [INFO] Creando directorio de distribucion...
if exist "%DIST_DIR%" rmdir /S /Q "%DIST_DIR%"
mkdir "%DIST_DIR%"

REM Copiar archivos principales
echo [INFO] Copiando archivos principales...
copy /Y "portable_v3_final\InstallGuard.Service.exe" "%DIST_DIR%\" >nul
copy /Y "portable_v3_final\appsettings.json" "%DIST_DIR%\" >nul

REM Copiar scripts de instalación
echo [INFO] Copiando scripts de instalacion...
copy /Y "install-portable-autostart.bat" "%DIST_DIR%\" >nul
copy /Y "uninstall-portable.bat" "%DIST_DIR%\" >nul
copy /Y "install-service-v3-final.bat" "%DIST_DIR%\install-as-service.bat" >nul

REM Copiar documentación
echo [INFO] Copiando documentacion...
copy /Y "VERIFICACION_DATOS_REALES.md" "%DIST_DIR%\" >nul
copy /Y "INTEGRACION_WEBAPP_SAAS.md" "%DIST_DIR%\" >nul

REM Crear README para distribución
echo [INFO] Creando README de distribucion...
echo # InstallGuard v3.0 FINAL - Paquete de Distribucion > "%DIST_DIR%\README_DISTRIBUCION.md"
echo. >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo ## Opciones de Instalacion >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo. >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo ### 1. Instalacion Portable (Recomendado para distribucion masiva) >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Ejecutar: `install-portable-autostart.bat` como administrador >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Se instala en: `C:\InstallGuard\` >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Auto-inicio configurado automaticamente >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Facil de distribuir via USB, red compartida, etc. >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo. >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo ### 2. Instalacion como Servicio de Windows >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Ejecutar: `install-as-service.bat` como administrador >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Se instala en: `C:\Program Files\InstallGuard\` >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Ejecuta como servicio del sistema >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo. >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo ## Desinstalacion >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Para version portable: `uninstall-portable.bat` >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Para servicio: usar Panel de Control o `sc delete InstallGuard` >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo. >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo ## Configuracion >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Editar `appsettings.json` para cambiar URL de la webapp >> "%DIST_DIR%\README_DISTRIBUCION.md"
echo - Por defecto apunta a: `http://localhost:4002/api` >> "%DIST_DIR%\README_DISTRIBUCION.md"

REM Crear script de instalación silenciosa
echo [INFO] Creando script de instalacion silenciosa...
echo @echo off > "%DIST_DIR%\install-silent.bat"
echo REM Instalacion silenciosa de InstallGuard >> "%DIST_DIR%\install-silent.bat"
echo net session ^>nul 2^>^&1 >> "%DIST_DIR%\install-silent.bat"
echo if %%errorLevel%% neq 0 exit /b 1 >> "%DIST_DIR%\install-silent.bat"
echo taskkill /F /IM "InstallGuard.Service.exe" ^>nul 2^>^&1 >> "%DIST_DIR%\install-silent.bat"
echo if not exist "C:\InstallGuard" mkdir "C:\InstallGuard" >> "%DIST_DIR%\install-silent.bat"
echo copy /Y "InstallGuard.Service.exe" "C:\InstallGuard\" ^>nul >> "%DIST_DIR%\install-silent.bat"
echo copy /Y "appsettings.json" "C:\InstallGuard\" ^>nul >> "%DIST_DIR%\install-silent.bat"
echo reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "InstallGuard" /t REG_SZ /d "\"C:\InstallGuard\InstallGuard.Service.exe\"" /f ^>nul >> "%DIST_DIR%\install-silent.bat"
echo start "" "C:\InstallGuard\InstallGuard.Service.exe" >> "%DIST_DIR%\install-silent.bat"

REM Mostrar información del paquete
echo.
echo ========================================
echo PAQUETE CREADO EXITOSAMENTE
echo ========================================
echo.
echo Directorio: %DIST_DIR%
echo Fecha: %DATE_STAMP%
echo.
echo CONTENIDO DEL PAQUETE:
dir "%DIST_DIR%" /B
echo.
echo TAMAÑO TOTAL:
for /f "tokens=3" %%a in ('dir "%DIST_DIR%" /-c ^| find "archivo(s)"') do echo %%a bytes

echo.
echo ========================================
echo INSTRUCCIONES DE DISTRIBUCION
echo ========================================
echo.
echo 1. Copia la carpeta '%DIST_DIR%' a una ubicacion compartida
echo 2. Distribuye via:
echo    - Unidad USB
echo    - Carpeta compartida de red
echo    - Email (comprimido)
echo    - Sistema de distribucion de software corporativo
echo.
echo 3. En cada equipo, ejecutar como administrador:
echo    - install-portable-autostart.bat (recomendado)
echo    - install-silent.bat (para instalacion automatizada)
echo.
echo Presiona cualquier tecla para continuar...
pause >nul 