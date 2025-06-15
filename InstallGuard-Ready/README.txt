========================================
    InstallGuard Agent - Servicio Windows
========================================

DESCRIPCIÓN:
InstallGuard Agent es un servicio de Windows que monitorea el software
instalado en el sistema y reporta la información al backend SoftCheck.

CARACTERÍSTICAS:
- Ejecuta como servicio de Windows (en segundo plano)
- Se inicia automáticamente con el sistema
- Modo pasivo (sin interrupciones al usuario)
- Envía inventario de software cada 15 minutos
- Comunicación segura con backend SoftCheck

========================================
INSTALACIÓN
========================================

REQUISITOS:
- Windows 10/11 o Windows Server 2016+
- Permisos de administrador
- .NET 8 Runtime (se incluye en el ejecutable)

PASOS:
1. Extraer todos los archivos en una carpeta
2. Hacer clic derecho en "install.bat"
3. Seleccionar "Ejecutar como administrador"
4. Seguir las instrucciones en pantalla

El servicio se instalará en: C:\Program Files\InstallGuard\

========================================
VERIFICACIÓN
========================================

Para verificar que el servicio está funcionando:

1. Ejecutar "status.bat" como administrador
2. O usar el comando: sc query "InstallGuard Agent"
3. O abrir Servicios de Windows (services.msc) y buscar "InstallGuard Agent"

Estado esperado: RUNNING (En ejecución)

========================================
CONFIGURACIÓN
========================================

El servicio está preconfigurado para:
- Backend: http://localhost:4002
- Team: myteam
- Modo: Pasivo (sin monitoreo en tiempo real)
- Inventario: Cada 15 minutos
- Ping: Cada minuto

Para cambiar la configuración:
1. Editar: C:\Program Files\InstallGuard\appsettings.json
2. Reiniciar el servicio: sc stop "InstallGuard Agent" && sc start "InstallGuard Agent"

========================================
COMANDOS ÚTILES
========================================

Ver estado:
sc query "InstallGuard Agent"

Iniciar servicio:
sc start "InstallGuard Agent"

Detener servicio:
sc stop "InstallGuard Agent"

Reiniciar servicio:
sc stop "InstallGuard Agent" && timeout /t 3 && sc start "InstallGuard Agent"

Ver logs:
eventvwr.msc (Visor de Eventos)
- Registros de Windows > Sistema
- Registros de aplicaciones y servicios > InstallGuard Service

========================================
DESINSTALACIÓN
========================================

Para desinstalar completamente:
1. Ejecutar "uninstall.bat" como administrador
2. O manualmente:
   - sc stop "InstallGuard Agent"
   - sc delete "InstallGuard Agent"
   - rmdir /s /q "C:\Program Files\InstallGuard"

========================================
SOLUCIÓN DE PROBLEMAS
========================================

El servicio no inicia:
1. Verificar que el backend esté ejecutándose en localhost:4002
2. Revisar logs en el Visor de Eventos
3. Verificar permisos de la carpeta de instalación

El servicio se detiene solo:
1. Revisar logs para errores específicos
2. Verificar conectividad de red
3. El servicio se reiniciará automáticamente en caso de fallo

Cambiar configuración:
1. Detener servicio: sc stop "InstallGuard Agent"
2. Editar: C:\Program Files\InstallGuard\appsettings.json
3. Iniciar servicio: sc start "InstallGuard Agent"

========================================
ARCHIVOS INCLUIDOS
========================================

install.bat      - Script de instalación
uninstall.bat    - Script de desinstalación
status.bat       - Verificar estado del servicio
README.txt       - Este archivo
InstallGuard.Service.exe - Ejecutable principal
*.pdb            - Archivos de depuración (opcionales)

========================================
SOPORTE
========================================

Para soporte técnico, revisar los logs del sistema y
contactar al administrador del sistema SoftCheck.

Logs importantes:
- Visor de Eventos > Sistema
- Visor de Eventos > InstallGuard Service

======================================== 