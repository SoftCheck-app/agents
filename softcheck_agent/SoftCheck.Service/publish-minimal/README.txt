========================================
    INSTALLGUARD AGENT - INSTALACIÓN SIMPLE
========================================

ARCHIVOS INCLUIDOS:
✓ InstallGuard.Service.exe  (Ejecutable principal - 16MB)
✓ install.bat              (Instalador automático)

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

CONFIGURACIÓN INCLUIDA:
- API Key: c07f7b249e2b4b970a04f97b169db6a5
- Team: myteam
- Backend: https://softcheck-v3.onrender.com
- Modo: PASIVO (sin notificaciones)

VERIFICACIÓN:
Después de instalar, abrir "Servicios" (services.msc)
y buscar "InstallGuard Agent" - debe estar "En ejecución"

DESINSTALACIÓN:
Ejecutar como administrador:
sc stop "InstallGuard Agent" && sc delete "InstallGuard Agent" && rmdir /s /q "C:\Program Files\InstallGuard"

SOPORTE:
Los logs se encuentran en el Visor de eventos de Windows
(Registros de Windows > Sistema)

========================================
Versión: 1.0 - Distribución Simplificada
======================================== 