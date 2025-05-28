# 🛡️ InstallGuard - Agente de Seguridad para Windows

**InstallGuard v4.0** es un agente de seguridad avanzado que monitorea instalaciones de software en tiempo real y mantiene un **inventario completo** sincronizado con la webapp SaaS.

## 🆕 **Novedades en v4.0 - Inventario Completo**

### **Nueva Funcionalidad Principal:**
- ✅ **Envío de inventario completo** cada 30 segundos
- ✅ **Sincronización total** de todas las aplicaciones instaladas
- ✅ **Envío optimizado en lotes** para mejor rendimiento
- ✅ **Redundancia completa** - no se pierde ninguna aplicación

### **Beneficios:**
- 🎯 **Visibilidad total:** La webapp siempre tiene el estado completo del sistema
- 🔄 **Sincronización automática:** Inventario actualizado cada 30 segundos
- 🛡️ **Tolerancia a fallos:** Si falla una detección, se recupera en el siguiente ciclo
- 📊 **Datos completos:** Incluye aplicaciones instaladas antes del agente

## 🚀 **Instalación Rápida**

### **Opción 1: Servicio de Windows (Recomendado)**
```bash
# Ejecutar como Administrador
install-service-v4-inventory.bat
```

### **Opción 2: Aplicación Portable**
```bash
# Ejecutar como usuario normal
install-portable-autostart.bat
```

## 📋 **Versiones Disponibles**

| Versión | Funcionalidad | Archivo de Instalación |
|---------|---------------|------------------------|
| **v4.0** | **Inventario Completo** | `install-service-v4-inventory.bat` |
| v3.0 | Detección + Reporte Individual | `install-service-v3-final.bat` |
| v2.0 | Solo Detección Local | `install-service.bat` |

## 🔧 **Configuración**

### **Configuración de la Webapp SaaS**
```json
{
  "SoftCheck": {
    "BaseUrl": "http://localhost:4002/api",
    "ApiKey": "305f98c40f6ab0224759d1725147ca1b"
  }
}
```

### **Frecuencia de Sincronización**
- **Inventario completo:** Cada 30 segundos
- **Detección de cambios:** Inmediata (WMI) + 30 segundos (Registry)
- **Envío en lotes:** 5 aplicaciones por request

## 📊 **Datos Enviados por Aplicación**

Cada aplicación en el inventario incluye:
- 📝 **Información básica:** Nombre, versión, fabricante
- 📁 **Ubicación:** Ruta de instalación, método de instalación
- 🔒 **Seguridad:** Firma digital, hash SHA256
- ⏰ **Timestamps:** Fecha de instalación, última ejecución
- 🏷️ **Metadatos:** Descripción, tamaño, arquitectura

## 🔍 **Métodos de Detección**

### **1. Monitoreo WMI (Inmediato)**
- Detecta eventos de instalación en tiempo real
- Cobertura: ~60-70% de instalaciones
- Latencia: 0-5 segundos

### **2. Monitoreo del Registro (Periódico)**
- Escanea el registro de Windows cada 30 segundos
- Cobertura: ~95% de instalaciones
- Latencia: 30-60 segundos

### **3. Inventario Completo (Nuevo en v4.0)**
- Envía todas las aplicaciones instaladas cada 30 segundos
- Cobertura: 100% del sistema
- Garantiza sincronización total

## 📈 **Rendimiento**

### **Consumo de Recursos**
- **CPU:** <1% en idle, 2-5% durante sincronización
- **RAM:** ~50-80 MB en ejecución normal
- **Red:** ~2-5 KB por aplicación enviada
- **Disco:** ~70 MB instalado, logs rotativos

### **Escalabilidad**
- **Sistema típico:** 50 aplicaciones = ~15 segundos de sincronización
- **Sistema grande:** 200 aplicaciones = ~60 segundos de sincronización
- **Optimización:** Envío en lotes paralelos

## 🛠️ **Administración**

### **Verificar Estado del Servicio**
```bash
# Verificar si está ejecutándose
sc query InstallGuard

# Ver logs en tiempo real
Get-Content "C:\Program Files\InstallGuard\logs\*.log" -Wait
```

### **Logs Importantes**
```
[INFO] Enviando inventario completo de aplicaciones a webapp...
[INFO] Encontradas X aplicaciones instaladas para enviar
[INFO] Inventario completado: X exitosas, Y fallidas
```

## 🔄 **Flujo de Funcionamiento v4.0**

```
🚀 Inicio del Agente
├── 📊 Carga inventario inicial (todas las apps)
├── 📡 Envía inventario completo a webapp
├── ✅ Inicia monitoreo continuo
└── 🔄 Cada 30 segundos:
    ├── 🔍 Detecta cambios (nuevas/eliminadas)
    ├── 📋 Recopila inventario completo actualizado
    ├── 📡 Envía todas las aplicaciones en lotes
    └── 📝 Registra estadísticas de sincronización
```

## 📚 **Documentación Completa**

- 📋 [Funcionalidad de Inventario Completo](FUNCIONALIDAD_INVENTARIO_COMPLETO.md)
- 🔧 [Cómo Funciona el Agente](COMO_FUNCIONA_EL_AGENTE.md)
- 📊 [Ejemplo de Funcionamiento Real](EJEMPLO_FUNCIONAMIENTO_REAL.md)
- 🔗 [Integración con Webapp SaaS](INTEGRACION_WEBAPP_SAAS.md)
- ✅ [Verificación de Datos Reales](VERIFICACION_DATOS_REALES.md)

## 🆘 **Soporte y Resolución de Problemas**

### **Problemas Comunes**
1. **Error 401 "Invalid API key"** → Verificar API key en base de datos
2. **No se envían datos** → Revisar conectividad con webapp
3. **Alto uso de CPU** → Verificar que no hay bucles en logs

### **Desinstalación**
```bash
# Ejecutar como Administrador
uninstall-service.bat
```

---

**🎯 InstallGuard v4.0** proporciona **visibilidad completa y continua** del inventario de software empresarial, asegurando que ninguna aplicación pase desapercibida y que la webapp SaaS tenga siempre el estado actualizado de todos los dispositivos monitoreados. 