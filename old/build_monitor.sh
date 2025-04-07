#!/bin/bash

# Script para compilar y ejecutar el monitor de instalaciones

echo "Compilando el monitor de instalaciones..."
echo "Verificando Xcode Command Line Tools..."

# Verificar si las herramientas de línea de comando están instaladas
if ! xcode-select -p &>/dev/null; then
    echo "Herramientas de línea de comando de Xcode no encontradas."
    echo "Instale Xcode Command Line Tools ejecutando: xcode-select --install"
    exit 1
fi

echo "Intentando compilar con opciones ampliadas..."
swiftc -o InstallMonitor InstallMonitor.swift -framework Cocoa -framework Foundation -sdk $(xcrun --show-sdk-path) -v

# Verificar si la compilación fue exitosa
if [ $? -eq 0 ]; then
    echo "Compilación exitosa. El ejecutable 'InstallMonitor' ha sido creado."
    
    # Dar permisos de ejecución
    chmod +x InstallMonitor
    
    echo ""
    echo "Para ejecutar el monitor, use:"
    echo "./InstallMonitor"
    
    # Preguntar si desea ejecutar ahora
    read -p "¿Desea ejecutar el monitor ahora? (s/n): " respuesta
    if [[ $respuesta == "s" || $respuesta == "S" ]]; then
        echo "Iniciando monitor de instalaciones..."
        ./InstallMonitor
    fi
else
    echo "Error durante la compilación. Intentando un método alternativo..."
    
    # Intentar con un enfoque alternativo usando swiftc con más opciones
    swiftc -o InstallMonitor InstallMonitor.swift -framework Cocoa -framework Foundation -import-objc-header /usr/include/objc/objc.h
    
    if [ $? -eq 0 ]; then
        echo "Compilación exitosa con método alternativo. El ejecutable 'InstallMonitor' ha sido creado."
        chmod +x InstallMonitor
        
        echo ""
        echo "Para ejecutar el monitor, use:"
        echo "./InstallMonitor"
        
        read -p "¿Desea ejecutar el monitor ahora? (s/n): " respuesta
        if [[ $respuesta == "s" || $respuesta == "S" ]]; then
            echo "Iniciando monitor de instalaciones..."
            ./InstallMonitor
        fi
    else
        echo "Error durante la compilación del monitor de instalaciones."
        echo "Recomendaciones para solucionar el problema:"
        echo "1. Asegúrese de tener Xcode Command Line Tools instalado actualizado:"
        echo "   xcode-select --install"
        echo "2. Verifique la versión de Swift: swift --version"
        echo "3. Intente crear un proyecto Xcode y compilar desde allí"
    fi
fi 