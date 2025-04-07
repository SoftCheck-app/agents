#!/bin/bash

# Script para compilar el agente de macOS

echo "Compilando la versión estándar del agente..."
swiftc -o MacOSAgent MacOSAgent.swift

# Verificar si la compilación fue exitosa
if [ $? -eq 0 ]; then
    echo "Compilación exitosa. El ejecutable 'MacOSAgent' ha sido creado."
else
    echo "Error durante la compilación de la versión estándar."
fi

echo ""
echo "Compilando la versión silenciosa avanzada del agente..."
swiftc -o MacOSAgentSilent MacOSAgentSilent.swift

# Verificar si la compilación fue exitosa
if [ $? -eq 0 ]; then
    echo "Compilación exitosa. El ejecutable 'MacOSAgentSilent' ha sido creado."
    echo ""
    echo "Ejecute ./MacOSAgent para iniciar la versión estándar."
    echo "Ejecute ./MacOSAgentSilent para iniciar la versión silenciosa avanzada."
else
    echo "Error durante la compilación de la versión silenciosa."
fi 