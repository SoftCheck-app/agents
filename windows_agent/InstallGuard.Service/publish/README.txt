========================================
    INSTALLGUARD AGENT - GUÍA DE INSTALACIÓN
========================================

DESCRIPCIÓN:
InstallGuard Agent es un servicio de Windows que monitorea el software instalado
en el sistema y reporta la información a la plataforma SoftCheck para verificación
de licencias y cumplimiento.

CARACTERÍSTICAS:
✓ Modo pasivo por defecto (sin interrupciones al usuario)
✓ Envío automático de inventario cada 15 minutos
✓ Detección de software instalado y actualizaciones
✓ Comunicación segura con backend SoftCheck
✓ Instalación como servicio de Windows (inicio automático)

REQUISITOS DEL SISTEMA:
- Windows 10/11 o Windows Server 2016+
- .NET 8.0 Runtime (incluido en el ejecutable)
- Permisos de administrador para instalación
- Conexión a Internet

INSTALACIÓN:
1. Descomprimir todos los archivos en una carpeta temporal
2. Hacer clic derecho en "install.bat" y seleccionar "Ejecutar como administrador"
3. Seguir las instrucciones en pantalla
4. El servicio se instalará y iniciará automáticamente

ARCHIVOS INCLUIDOS:
- InstallGuard.Service.exe    (Ejecutable principal - 16MB)
- appsettings.json           (Archivo de configuración)
- install.bat                (Script de instalación)
- uninstall.bat              (Script de desinstalación)
- README.txt                 (Este archivo)

CONFIGURACIÓN:
El archivo appsettings.json contiene la configuración del agente.
NO modificar a menos que sea indicado por el soporte técnico.

VERIFICACIÓN DE INSTALACIÓN:
Después de la instalación, puede verificar que el servicio esté funcionando:
1. Abrir "Servicios" (services.msc)
2. Buscar "InstallGuard Agent"
3. Verificar que el estado sea "En ejecución"

DESINSTALACIÓN:
1. Hacer clic derecho en "uninstall.bat" y seleccionar "Ejecutar como administrador"
2. Seguir las instrucciones en pantalla

COMANDOS ÚTILES:
- Ver estado del servicio: sc query "InstallGuard Agent"
- Detener servicio: sc stop "InstallGuard Agent"
- Iniciar servicio: sc start "InstallGuard Agent"
- Reiniciar servicio: sc stop "InstallGuard Agent" && sc start "InstallGuard Agent"

FUNCIONAMIENTO:
- El agente funciona en modo PASIVO por defecto
- NO interrumpe al usuario con notificaciones
- Envía inventario de software cada 15 minutos
- Realiza ping al servidor cada minuto para mantener conexión
- Los logs se almacenan en el Visor de eventos de Windows

SOPORTE TÉCNICO:
Para soporte técnico o preguntas, contactar al administrador del sistema
que proporcionó este software.

PRIVACIDAD:
El agente solo recopila información sobre software instalado (nombres, versiones,
fabricantes) y metadatos del sistema. NO accede a archivos personales ni
datos confidenciales.

========================================
Versión: 1.0
Fecha: 2024
======================================== 