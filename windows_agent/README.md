# SoftCheck Windows Agent

Este agente de Windows monitorea continuamente las instalaciones de aplicaciones, verifica su autorización con un servidor central y gestiona el bloqueo o eliminación de aplicaciones no autorizadas.

## Características principales

* **Detección automática** de nuevas aplicaciones instaladas
* **Verificación de software** con servidor central para determinar si está autorizado
* **Modos de operación**: activo (bloquea aplicaciones) o pasivo (solo monitoreo)
* **Cuarentena** para aplicaciones no autorizadas
* **Actualizaciones automáticas** del propio agente
* **Funciona como servicio** en segundo plano

## Requisitos

- Windows 8.1/10/11 o Windows Server 2016/2019/2022
- PowerShell 5.1 o superior
- Permisos de administrador para instalación y algunas operaciones

## Instalación

### Como servicio (recomendado)

1. Ejecuta PowerShell como administrador
2. Navega al directorio donde se encuentra el script
3. Ejecuta: `.\WindowsInstallAgent.ps1 install`

### Ejecución manual

1. Ejecuta PowerShell como administrador
2. Navega al directorio donde se encuentra el script
3. Ejecuta: `.\WindowsInstallAgent.ps1 run`

## Desinstalación

1. Ejecuta PowerShell como administrador
2. Navega al directorio donde se encuentra el script
3. Ejecuta: `.\WindowsInstallAgent.ps1 uninstall`

## Configuración

La configuración se guarda en el archivo `%LOCALAPPDATA%\SoftCheck\agent_config.json`. Este archivo se sincroniza automáticamente con el servidor central.

### Ajustes principales

- **BACKEND_URL**: URL del servidor de backend
- **API_KEY**: Clave de API para autenticación con el servidor
- **SCAN_INTERVAL**: Intervalo en segundos entre escaneos de nuevas aplicaciones
- **AGENT_STATUS**: Estado del agente (active/inactive)
- **AGENT_MODE**: Modo de operación (active/passive)

## Funcionamiento

1. **Monitoreo continuo**: El agente escanea periódicamente las aplicaciones instaladas.
2. **Detección**: Al detectar una nueva instalación, recopila información detallada.
3. **Verificación**: Consulta con el servidor central si la aplicación está autorizada.
4. **Acción**: Según la respuesta del servidor, permite la ejecución, bloquea temporalmente, o elimina la aplicación.

## Modos de operación

- **Activo**: Bloquea automáticamente las aplicaciones no autorizadas
- **Pasivo**: Solo monitorea e informa, sin tomar acciones restrictivas

## Comparación con la versión para macOS

Este agente es el equivalente para Windows del agente macOS, con las siguientes adaptaciones:

- Usa PowerShell en lugar de Bash
- Implementa métodos específicos de Windows para detectar aplicaciones (registro y sistema de archivos)
- Utiliza ACLs de Windows para restringir ejecución en lugar de permisos Unix
- Se instala como servicio de Windows usando NSSM

## Soporte técnico

Para soporte técnico, comuníquese con el administrador del sistema o con el equipo de seguridad. 