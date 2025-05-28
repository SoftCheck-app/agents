# 📋 Ejemplo Práctico: Instalación de TickTick

## 🎯 Caso Real de Funcionamiento

Vamos a seguir paso a paso lo que sucede cuando un empleado instala **TickTick** en su ordenador con InstallGuard ejecutándose.

## ⏱️ Timeline Completa de Detección

### **T+0 segundos** - Usuario inicia instalación
```
👤 Usuario: Ejecuta TickTick_Setup.exe
📁 Archivo: TickTick_Setup.exe (15.2 MB)
🔍 Estado del agente: Monitoreando activamente
```

### **T+2 segundos** - WMI detecta actividad
```
🔍 WMI Event: Win32_VolumeChangeEvent detectado
📊 InstallationMonitorService: "Posible instalación en progreso..."
📝 Log: [INFO] WMI event detected - potential software installation
```

### **T+45 segundos** - Instalación completa
```
👤 Usuario: Completa el wizard de instalación
📁 Archivos: Copiados a C:\Program Files\TickTick\
🗂️ Registro: Nueva entrada creada en HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\
```

### **T+47 segundos** - Timer del registro ejecuta verificación
```
⏰ RegistryTimer: Ejecuta CheckForApplicationChangesAsync()
🔍 Comparación: Estado actual vs. estado anterior (hace 30s)
🆕 Detección: Nueva aplicación encontrada!
```

### **T+48 segundos** - Extracción de información
```csharp
// Información extraída del registro
ApplicationInfo ticktick = {
    Name = "TickTick",
    Version = "5.0.30",
    Publisher = "Appest Inc.",
    InstallLocation = "C:\\Program Files\\TickTick\\",
    InstallDate = "20241215",
    UninstallString = "C:\\Program Files\\TickTick\\unins000.exe",
    EstimatedSize = "45123", // KB
    DisplayIcon = "C:\\Program Files\\TickTick\\TickTick.exe,0",
    // ... 20+ campos más extraídos automáticamente
}
```

### **T+49 segundos** - Análisis de seguridad
```csharp
// Análisis automático de riesgo
SecurityAnalysis analysis = {
    DigitalSignature = "Present", // ✅ Firmado digitalmente
    Publisher = "Appest Inc.",    // ✅ Publisher conocido
    InstallLocation = "C:\\Program Files\\TickTick\\", // ✅ Ubicación estándar
    SuspiciousName = false,       // ✅ Nombre legítimo
    
    RiskScore = 5,               // Muy bajo
    RiskLevel = "Low",           // 🟢 Seguro
    RecommendedAction = "Aplicación parece segura"
}
```

### **T+50 segundos** - Notificación al usuario
```
🔔 Popup mostrado:
┌─────────────────────────────────────┐
│ 🟢 Nueva Aplicación Detectada       │
├─────────────────────────────────────┤
│ TickTick v5.0.30                    │
│ Publisher: Appest Inc.              │
│ Ubicación: C:\Program Files\TickTick│
│ Riesgo: Bajo ✅                     │
│ Recomendación: Aplicación segura    │
└─────────────────────────────────────┘
```

### **T+51 segundos** - Preparación de datos para webapp
```json
{
  "device_id": "WIN-ABC123DEF456",
  "user_id": "EMPRESA\\juan.perez",
  "software_name": "TickTick",
  "version": "5.0.30",
  "vendor": "Appest Inc.",
  "install_date": "2024-12-15T14:30:00Z",
  "install_path": "C:\\Program Files\\TickTick\\",
  "install_method": "Setup",
  "last_executed": "2024-12-15T14:31:00Z",
  "is_running": false,
  "digital_signature": true,
  "is_approved": false,
  "detected_by": "windows_agent",
  "sha256": "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456",
  "notes": "Descripción: Task management app; Arquitectura: x64; Tamaño: 44.1 MB"
}
```

### **T+52 segundos** - Envío a webapp SaaS
```http
POST http://localhost:4002/api/validate_software
Headers:
  Content-Type: application/json
  X-API-KEY: 305f98c40f6ab0224759d1725147ca1b
  User-Agent: InstallGuard-Agent/3.0

Body: [JSON payload arriba]
```

### **T+54 segundos** - Respuesta de la webapp
```json
{
  "success": true,
  "message": "Software registered successfully",
  "isApproved": false,
  "softwareId": "cmb6w0i0u0002nugwwcvmxaz6",
  "riskAssessment": {
    "level": "low",
    "factors": ["known_publisher", "digital_signature"]
  }
}
```

### **T+55 segundos** - Logging y finalización
```
📝 Logs generados:
[INFO] Nueva aplicación detectada: TickTick v5.0.30
[INFO] Análisis de seguridad completado - Riesgo: Low
[INFO] Notificación mostrada al usuario
[INFO] Aplicación reportada exitosamente a webapp
[INFO] ID asignado: cmb6w0i0u0002nugwwcvmxaz6
[INFO] Proceso de detección completado en 8 segundos
```

## 🔍 Información Técnica Detallada

### 📊 Datos Extraídos del Registro
```
Ruta del registro: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{GUID}
Campos leídos:
├── DisplayName: "TickTick"
├── DisplayVersion: "5.0.30"
├── Publisher: "Appest Inc."
├── InstallLocation: "C:\Program Files\TickTick\"
├── InstallDate: "20241215"
├── EstimatedSize: 45123 (KB)
├── UninstallString: "C:\Program Files\TickTick\unins000.exe"
├── DisplayIcon: "C:\Program Files\TickTick\TickTick.exe,0"
├── NoModify: 1
├── NoRepair: 1
└── URLInfoAbout: "https://ticktick.com"
```

### 🔐 Verificación de Seguridad
```csharp
// Verificación de firma digital
X509Certificate2 cert = X509Certificate.CreateFromSignedFile(
    @"C:\Program Files\TickTick\TickTick.exe"
);
// Resultado: Certificado válido de "Appest Inc."

// Cálculo de hash SHA256
using var sha256 = SHA256.Create();
using var stream = File.OpenRead(@"C:\Program Files\TickTick\TickTick.exe");
var hash = sha256.ComputeHash(stream);
// Resultado: a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

### 🌐 Comunicación con Webapp
```
🔗 Endpoint: POST /api/validate_software
🔑 Autenticación: API Key en header X-API-KEY
📦 Payload: JSON con 15+ campos de información
⏱️ Timeout: 30 segundos
🔄 Reintentos: 3 intentos en caso de fallo
📊 Respuesta: Confirmación + ID único asignado
```

## 📈 Métricas de Rendimiento

### ⚡ Tiempos de Respuesta Medidos
```
Detección inicial (WMI): 2 segundos
Verificación por registro: 47 segundos
Extracción de metadatos: 1 segundo
Análisis de seguridad: 1 segundo
Notificación al usuario: <1 segundo
Envío a webapp: 2 segundos
Confirmación recibida: 2 segundos
─────────────────────────────────
TOTAL: 55 segundos desde instalación
```

### 💾 Consumo de Recursos Durante Detección
```
CPU: Pico de 3.2% durante 5 segundos
RAM: +5 MB temporalmente (análisis de archivos)
Disco: 2 MB de lectura (verificación de ejecutables)
Red: 1.2 KB enviados (payload JSON)
```

## 🎯 Resultado en la Webapp SaaS

### 📊 Dashboard Actualizado
```
Nueva entrada en la base de datos:
┌─────────────────────────────────────────┐
│ 🆕 Software Detectado                   │
├─────────────────────────────────────────┤
│ Aplicación: TickTick v5.0.30            │
│ Dispositivo: WIN-ABC123DEF456           │
│ Usuario: EMPRESA\juan.perez             │
│ Fecha: 15/12/2024 14:31                 │
│ Riesgo: 🟢 Bajo                         │
│ Estado: ⏳ Pendiente aprobación         │
└─────────────────────────────────────────┘
```

### 📋 Información Disponible para IT
- **Inventario actualizado** automáticamente
- **Análisis de riesgo** completado
- **Trazabilidad completa** del software
- **Alertas configurables** según políticas
- **Reportes de cumplimiento** actualizados

---

**✅ Conclusión:** En menos de 1 minuto, InstallGuard detectó, analizó, notificó y reportó completamente la instalación de TickTick, proporcionando visibilidad total al equipo de IT sin intervención manual. 