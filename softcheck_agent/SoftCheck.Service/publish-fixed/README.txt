========================================
    INSTALLGUARD AGENT - VERSIÓN CORREGIDA
========================================

ARCHIVOS INCLUIDOS:
✓ InstallGuard.Service.exe  (Ejecutable principal - 38MB)
✓ install.bat              (Instalador automático)

CORRECCIONES EN ESTA VERSIÓN:
✓ Problema de serialización JSON resuelto
✓ Compatible con trimming deshabilitado
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

NOTA TÉCNICA:
Esta versión tiene el trimming deshabilitado para evitar
problemas de serialización JSON. El tamaño es mayor pero
la estabilidad está garantizada.

========================================
Versión: 1.1 - Corrección de Serialización
======================================== 