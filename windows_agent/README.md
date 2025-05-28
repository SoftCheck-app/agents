# InstallGuard Service v3.0

## 🛡️ Descripción

InstallGuard es un servicio de Windows que detecta automáticamente las instalaciones de aplicaciones en el sistema, analiza su nivel de riesgo de seguridad, muestra notificaciones informativas al usuario y **reporta automáticamente todos los datos a una webapp SaaS** para gestión centralizada y aprobación de software.

## ✨ Características

- **🔍 Detección automática** de instalaciones de aplicaciones
- **🛡️ Análisis de seguridad** en tiempo real con puntuación de riesgo
- **📱 Notificaciones popup** informativas y no intrusivas
- **⚡ Monitoreo continuo** usando WMI y registro de Windows
- **🎯 Filtrado inteligente** de componentes del sistema
- **📊 Logging completo** en Event Viewer de Windows
- **🌐 Reporte automático** a webapp SaaS para gestión centralizada
- **🔄 Sincronización** de datos con base de datos central
- **✅ Sistema de aprobación** de software empresarial

## 🚀 Instalación

### Opción 1: Instalación como Servicio de Windows (Recomendado)

1. **Ejecutar como administrador** el archivo `install-service-v3.bat`
2. El servicio se instalará automáticamente y comenzará a monitorear
3. Se configurará automáticamente la integración con la webapp SaaS

### Opción 2: Ejecución Portable

1. Navegar a la carpeta `portable_v3/`
2. Ejecutar `InstallGuard.Service.exe` directamente

## 🗑️ Desinstalación

Ejecutar como administrador el archivo `uninstall-service.bat`

## ⚙️ Configuración

El archivo `appsettings.json` contiene la configuración del servicio:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  },
  "Backend": {
    "BaseUrl": "http://localhost:4002",
    "ApiKey": "83dc386a4a636411e068f86bbe5de3bd"
  },
  "SoftCheck": {
    "BaseUrl": "http://localhost:4002/api",
    "ApiKey": "305f98c40f6ab0224759d1725147ca1b"
  },
  "Features": {
    "EnableDriver": false,
    "EnableInstallationMonitoring": true
  }
}
```

### Configuración de Webapp SaaS

- **SoftCheck.BaseUrl**: URL de la API de la webapp SaaS
- **SoftCheck.ApiKey**: Clave de autenticación para la webapp
- Los datos se envían automáticamente al endpoint `/validate_software`

## 🔒 Análisis de Seguridad

El sistema evalúa cada aplicación instalada con los siguientes criterios:

### Niveles de Riesgo:
- **🟢 LOW (0-29 puntos)**: Aplicación parece segura
- **🟡 MEDIUM (30-49 puntos)**: Monitorear comportamiento
- **🟠 HIGH (50-69 puntos)**: Verificar legitimidad
- **🔴 CRITICAL (70+ puntos)**: Desinstalar inmediatamente

### Factores de Riesgo:
- Sin firma digital: +30 puntos
- Publisher desconocido: +20 puntos
- Ubicación sospechosa: +25 puntos
- Nombre sospechoso: +40 puntos

## 📋 Información de la Notificación

Cada popup incluye:
- 📱 Nombre y versión de la aplicación
- 🏢 Publisher/Desarrollador
- 📂 Ubicación de instalación
- 💾 Tamaño estimado
- 🏗️ Arquitectura (x86/x64)
- 🛡️ Nivel de riesgo calculado
- ⚠️ Alertas de seguridad específicas
- 💡 Recomendaciones de acción

## 🌐 Integración con Webapp SaaS

### Datos Reportados Automáticamente:
- 🆔 ID único del dispositivo
- 👤 Usuario que instaló la aplicación
- 📦 Información completa de la aplicación
- 🔐 Hash SHA256 del ejecutable
- ⏰ Fecha y hora de instalación
- 🔍 Estado de firma digital
- 📊 Análisis de riesgo completo

### Beneficios:
- **📊 Visibilidad centralizada** de todo el software instalado
- **✅ Proceso de aprobación** empresarial
- **🔍 Auditoría completa** de instalaciones
- **⚡ Respuesta rápida** a amenazas de seguridad

## 🔧 Requisitos del Sistema

- Windows 10/11
- .NET 8.0 Runtime (incluido en el ejecutable)
- Permisos de administrador para instalación

## 📊 Rendimiento

- **CPU**: <1% en uso normal
- **RAM**: ~15-20MB adicional
- **Tamaño**: ~75MB ejecutable autocontenido
- **Red**: Mínimo uso para reportes a webapp

## 📝 Logs

Los logs del servicio se pueden ver en:
- **Event Viewer** → Windows Logs → Application
- **Fuente**: InstallGuard Service

## 🏗️ Desarrollo

### Estructura del Proyecto:
- `InstallGuard.Service/` - Servicio principal
- `InstallGuard.Common/` - Modelos y utilidades compartidas
- `InstallGuard.Driver/` - Driver de kernel (deshabilitado)
- `portable_v3/` - Ejecutable autocontenido v3.0

### Compilación:
```bash
dotnet publish InstallGuard.Service -c Release -r win-x64 --self-contained -o portable_v3
```

### Nuevos Servicios v3.0:
- `SoftwareReportingService` - Comunicación con webapp SaaS
- `ISoftwareReportingService` - Interfaz del servicio de reporte

## 📄 Licencia

Este proyecto está bajo licencia MIT.

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor, abra un issue antes de enviar un pull request.

---

**InstallGuard v3.0** - Protección inteligente con gestión centralizada para tu sistema Windows 🛡️🌐 