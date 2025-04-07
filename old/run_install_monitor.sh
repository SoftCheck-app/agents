#!/bin/bash

# Script para ejecutar el monitor de instalaciones basado en AppleScript

echo "Iniciando el monitor de instalaciones de AppleScript..."
echo "Este monitor detectará nuevas aplicaciones instaladas en /Applications y solicitará aprobación."

# Ejecutar el script de AppleScript
osascript InstallationMonitor.applescript

# Nota: Para detener el monitor, presione Ctrl+C o cierre la ventana de Terminal 