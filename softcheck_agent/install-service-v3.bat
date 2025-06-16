@echo off
echo ========================================
echo InstallGuard Service v3.0 - Instalador
echo ========================================
echo.
echo NUEVAS FUNCIONALIDADES EN v3.0:
echo - Deteccion automatica de instalaciones de aplicaciones
echo - Analisis de riesgo de seguridad en tiempo real
echo - Popups informativos al usuario con datos completos
echo - NUEVO: Reporte automatico a webapp SaaS
echo - NUEVO: Integracion con sistema de aprobacion de software
echo - NUEVO: Sincronizacion de datos con base de datos central
echo.

REM Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Este script requiere permisos de administrador.
    echo Por favor, ejecute como administrador.
    pause
    exit /b 1
)

echo Verificando si el servicio ya existe...
sc query "InstallGuard Service" >nul 2>&1
if %errorLevel% equ 0 (
    echo El servicio ya existe. Deteniendolo...
    sc stop "InstallGuard Service"
    timeout /t 3 /nobreak >nul
    
    echo Eliminando servicio existente...
    sc delete "InstallGuard Service"
    timeout /t 2 /nobreak >nul
)

echo.
echo Copiando archivos del servicio...
if not exist "C:\Program Files\InstallGuard" mkdir "C:\Program Files\InstallGuard"

xcopy /Y /E "portable_v3\*" "C:\Program Files\InstallGuard\"
if %errorLevel% neq 0 (
    echo ERROR: No se pudieron copiar los archivos.
    pause
    exit /b 1
)

echo.
echo Instalando servicio de Windows...
sc create "InstallGuard Service" binPath= "C:\Program Files\InstallGuard\InstallGuard.Service.exe" start= auto DisplayName= "InstallGuard Service v3.0"
if %errorLevel% neq 0 (
    echo ERROR: No se pudo crear el servicio.
    pause
    exit /b 1
)

echo.
echo Configurando descripcion del servicio...
sc description "InstallGuard Service" "Servicio de monitoreo de instalaciones con reporte automatico a webapp SaaS. Detecta nuevas aplicaciones, analiza riesgos de seguridad y sincroniza datos con el sistema central."

echo.
echo Iniciando servicio...
sc start "InstallGuard Service"
if %errorLevel% neq 0 (
    echo ADVERTENCIA: El servicio se instalo pero no se pudo iniciar automaticamente.
    echo Puede iniciarlo manualmente desde services.msc
) else (
    echo Servicio iniciado exitosamente.
)

echo.
echo ========================================
echo INSTALACION COMPLETADA
echo ========================================
echo.
echo El servicio InstallGuard v3.0 ha sido instalado y configurado.
echo.
echo FUNCIONALIDADES ACTIVAS:
echo [x] Monitoreo de instalaciones en tiempo real
echo [x] Analisis de riesgo de seguridad automatico
echo [x] Notificaciones popup al usuario
echo [x] Reporte automatico a webapp SaaS
echo [x] Sincronizacion con base de datos central
echo.
echo CONFIGURACION:
echo - Ubicacion: C:\Program Files\InstallGuard\
echo - Configuracion: appsettings.json
echo - Logs: Event Viewer (InstallGuard Service)
echo.
echo WEBAPP SAAS:
echo - URL: http://localhost:4002/api
echo - Endpoint: /validate_software
echo - Autenticacion: API Key configurada
echo.
echo Para verificar el estado del servicio:
echo   sc query "InstallGuard Service"
echo.
echo Para ver los logs:
echo   eventvwr.msc ^> Windows Logs ^> Application
echo   Buscar eventos de "InstallGuard Service"
echo.
pause 