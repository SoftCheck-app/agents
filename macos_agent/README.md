# Agente de Escaneo de Software para macOS

Este proyecto contiene varias versiones de un agente para macOS que escanea aplicaciones instaladas en el sistema y envía esta información a una API externa.

## Versiones disponibles

### 1. Versión Estándar (MacOSAgent.swift)
- Funcionalidad básica de escaneo
- Envío de datos a la API
- Ejecución en segundo plano
- Requiere compilación con Swift

### 2. Versión Silenciosa Avanzada (MacOSAgentSilent.swift)
- Completamente silenciosa (sin mensajes en consola)
- Enmascaramiento del proceso en Activity Monitor
- Autoarranque mediante LaunchAgents
- Escaneo periódico (cada 24 horas)
- Información detallada de las aplicaciones (nombre y versión)
- Requiere compilación con Swift

### 3. Versión en Bash (AppScanner.sh)
- No requiere compilación
- Compatible con cualquier versión de macOS
- Funcionalidad similar a la versión silenciosa avanzada
- Autoarranque mediante LaunchAgents
- Escaneo periódico (cada 10 segundos)
- Información detallada de las aplicaciones (nombre, versión, ruta, SHA256, usuario, MAC)
- Envío en formato JSON

### 4. Monitor de Instalaciones (InstallationMonitor.applescript) - NUEVO
- Intercepta instalaciones de nuevas aplicaciones en /Applications
- Muestra un popup de aprobación cuando se detecta una nueva aplicación
- Permite aprobar o denegar la instalación
- Envía información detallada al backend en formato JSON
- No requiere compilación, funciona con el AppleScript integrado en macOS
- Fácil de instalar y usar en cualquier versión de macOS

## Funcionalidades comunes

- Escanea aplicaciones en los directorios de aplicaciones
- Envía datos a través de una API utilizando curl o URLSession
- Ejecuta en segundo plano

## Requisitos

### Para las versiones Swift:
- macOS 10.13 o superior
- Xcode Command Line Tools instalado

### Para la versión Bash y AppleScript:
- macOS (cualquier versión)
- Permisos de ejecución para el script

## Instalación

### Versiones Swift
Para compilar las versiones en Swift (si tu entorno es compatible):

```bash
chmod +x build.sh
./build.sh
```

### Monitor de Instalaciones (AppleScript)
Para ejecutar el monitor de instalaciones:

```bash
chmod +x run_install_monitor.sh
./run_install_monitor.sh
```

### Versión Bash
No requiere compilación, simplemente dale permisos de ejecución:

```bash
chmod +x AppScanner.sh
```

## Ejecución

### Versión Estándar (Swift)
```bash
./MacOSAgent
```

### Versión Silenciosa Avanzada (Swift)
```bash
./MacOSAgentSilent
```

### Versión Bash
```bash
./AppScanner.sh
```

### Monitor de Instalaciones (AppleScript)
```bash
./run_install_monitor.sh
```

Las versiones silenciosa avanzada y bash se configuran automáticamente para iniciarse cada vez que el sistema arranque.

## Modo de prueba

Para ejecutar la versión Bash en modo de prueba sin enviar datos a la API:

```bash
./run_test.sh
```

## Desinstalación

### Para la versión Swift Silenciosa:
```bash
rm ~/Library/LaunchAgents/com.system.maintenance.plist
killall MacOSAgentSilent
```

### Para la versión Bash:
```bash
rm ~/Library/LaunchAgents/com.system.appscanner.plist
killall AppScanner.sh
```

### Para el Monitor de Instalaciones (AppleScript):
```bash
# Simplemente cierre la ventana de Terminal donde se está ejecutando
# o presione Ctrl+C para detener el proceso
```

## Funcionamiento del Monitor de Instalaciones

1. El monitor observa el directorio `/Applications` en busca de cambios
2. Cuando detecta una nueva aplicación, muestra un popup de aprobación con los detalles
3. Si el usuario aprueba, envía los datos al backend y permite la instalación
4. Si el usuario deniega, intenta eliminar la aplicación (requiere contraseña de administrador)

El popup muestra toda la información de la aplicación, incluyendo:
- Nombre de la aplicación
- Versión
- Ruta completa
- Hash SHA256 del ejecutable principal
- Nombre de usuario
- Dirección MAC del sistema

## Configuración

El backend por defecto está configurado en `http://127.0.0.1:5000`. Para cambiar esta URL:
- En la versión AppleScript: Edita la variable `backendURL` al inicio del archivo InstallationMonitor.applescript
- En la versión Bash: Edita la variable `api_url` en AppScanner.sh

## Ventajas de la versión AppleScript

- **No requiere compilación**: Funciona directamente en macOS sin herramientas adicionales
- **Interfaz visual nativa**: Utiliza diálogos nativos de macOS para mostrar información
- **Permisos de administrador**: Puede solicitar permisos para eliminar aplicaciones no deseadas
Este agente es solo para fines educativos. Utilícelo con responsabilidad y siempre respetando la privacidad de los usuarios. 