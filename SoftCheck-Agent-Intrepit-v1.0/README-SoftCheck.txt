========================================
    SOFTCHECK AGENT - INTREPIT
========================================

DESCRIPCION:
SoftCheck Agent es un servicio de Windows que monitorea las aplicaciones instaladas
en el sistema y reporta la información al backend de SoftCheck.

CONFIGURACION:
- Team ID: intrepit
- API Key: 89888ecba1b4a5a26716e80a396fd5db
- URL Backend: https://intrepit.softcheck.app
- Modo: Pasivo (inventario cada 15 minutos)

INSTALACION:
1. Ejecutar como administrador: install-softcheck.bat
2. El servicio se instalará y iniciará automáticamente

DESINSTALACION:
1. Ejecutar como administrador: uninstall-softcheck.bat

VERIFICAR ESTADO:
1. Ejecutar: status-softcheck.bat

ARCHIVOS INCLUIDOS:
- SoftCheck.Service.exe (Ejecutable principal)
- appsettings.json (Configuración)
- install-softcheck.bat (Instalador)
- uninstall-softcheck.bat (Desinstalador)
- status-softcheck.bat (Verificador de estado)

CARACTERISTICAS:
- Monitoreo pasivo de aplicaciones instaladas
- Envío de inventario cada 15 minutos
- Comunicación segura con backend HTTPS
- Servicio de Windows nativo
- Logs en Event Viewer

SOPORTE:
Para soporte técnico, contactar al equipo de intrepit.

========================================
Versión: 1.0
Fecha: Junio 2025
======================================== 