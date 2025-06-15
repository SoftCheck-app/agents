========================================
    INSTALLGUARD AGENT - VERSIÓN FINAL
========================================

ARCHIVOS INCLUIDOS:
✓ InstallGuard.Service.exe  (Ejecutable principal - 38MB)
✓ install.bat              (Instalador automático)

CORRECCIONES EN ESTA VERSIÓN:
✓ Problema de serialización JSON resuelto
✓ Configuración de backend unificada
✓ Conecta correctamente a localhost:4002
✓ Funcionamiento estable garantizado

INSTALACIÓN RÁPIDA:
1. Clic derecho en "install.bat"
2. Seleccionar "Ejecutar como administrador"
3. ¡Listo! El agente se instalará automáticamente

CARACTERÍSTICAS:
✓ Solo 2 archivos necesarios
✓ Configuración automática incluida
✓ Modo pasivo (sin interrupciones)
✓ Envío de inventario cada 15 minutos
✓ Instalación como servicio de Windows
✓ Inicio automático con el sistema
✓ Serialización JSON optimizada
✓ Backend local configurado

CONFIGURACIÓN INCLUIDA:
- API Key: c07f7b249e2b4b970a04f97b169db6a5
- Team: myteam
- Backend: http://localhost:4002 (LOCAL)
- Modo: PASIVO (sin notificaciones)

ENDPOINTS UTILIZADOS:
- Ping: http://localhost:4002/api/agents/ping
- Validación: http://localhost:4002/api/validate_software
- Health: http://localhost:4002/api/health

VERIFICACIÓN:
Después de instalar, abrir "Servicios" (services.msc)
y buscar "InstallGuard Agent" - debe estar "En ejecución"

DESINSTALACIÓN:
Ejecutar como administrador:
sc stop "InstallGuard Agent" && sc delete "InstallGuard Agent" && rmdir /s /q "C:\Program Files\InstallGuard"

SOPORTE:
Los logs se encuentran en el Visor de eventos de Windows
(Registros de Windows > Sistema)

NOTA TÉCNICA:
Esta versión tiene la configuración unificada bajo "ApiSettings"
y se conecta correctamente al backend local en localhost:4002.

========================================
Versión: 1.2 - Configuración Unificada
======================================== 