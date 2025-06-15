@echo off
echo ========================================
echo    InstallGuard Agent - Diagnóstico
echo ========================================
echo.

echo INFORMACION DEL SISTEMA:
echo Directorio actual: %CD%
echo Usuario actual: %USERNAME%
echo Fecha/Hora: %DATE% %TIME%
echo.

echo VERIFICACION DE PERMISOS:
net session >nul 2>&1
if %errorLevel% == 0 (
    echo ✓ Ejecutándose como administrador
) else (
    echo ❌ NO se está ejecutando como administrador
    echo   SOLUCION: Hacer clic derecho y "Ejecutar como administrador"
)
echo.

echo ARCHIVOS EN DIRECTORIO ACTUAL:
echo Todos los archivos:
dir /b
echo.
echo Solo archivos .exe:
dir *.exe /b 2>nul
if errorlevel 1 echo   (No se encontraron archivos .exe)
echo.

echo VERIFICACION ESPECIFICA:
if exist "InstallGuard.Service.exe" (
    echo ✓ InstallGuard.Service.exe: ENCONTRADO
    for %%I in ("InstallGuard.Service.exe") do (
        echo   Tamaño: %%~zI bytes
        echo   Fecha: %%~tI
    )
    
    REM Verificar si el archivo está bloqueado
    echo   Verificando acceso...
    type "InstallGuard.Service.exe" >nul 2>&1
    if errorlevel 1 (
        echo   ❌ ADVERTENCIA: El archivo puede estar bloqueado o corrupto
    ) else (
        echo   ✓ Archivo accesible
    )
) else (
    echo ❌ InstallGuard.Service.exe: NO ENCONTRADO
)

if exist "install.bat" (
    echo ✓ install.bat: ENCONTRADO
) else (
    echo ❌ install.bat: NO ENCONTRADO
)

if exist "appsettings.json" (
    echo ✓ appsettings.json: ENCONTRADO
) else (
    echo ℹ appsettings.json: No encontrado (se creará durante instalación)
)
echo.

echo VERIFICACION DE SERVICIO EXISTENTE:
sc query "InstallGuard Agent" >nul 2>&1
if %errorLevel% == 0 (
    echo ✓ Servicio "InstallGuard Agent" ya existe
    sc query "InstallGuard Agent" | findstr "STATE"
) else (
    echo ℹ Servicio "InstallGuard Agent" no existe (normal para primera instalación)
)
echo.

echo ========================================
echo Diagnóstico completado
echo ========================================
echo.
echo Si InstallGuard.Service.exe aparece como "NO ENCONTRADO":
echo 1. Verifique que extrajo TODOS los archivos del ZIP
echo 2. Verifique que no hay restricciones de antivirus
echo 3. Intente descargar nuevamente el ZIP
echo.
echo Si aparece como "ENCONTRADO" pero install.bat falla:
echo 1. Ejecute install.bat como administrador
echo 2. Verifique que no hay espacios en la ruta de carpetas
echo 3. Intente desde una carpeta más simple (ej: C:\temp\)
echo.
pause 