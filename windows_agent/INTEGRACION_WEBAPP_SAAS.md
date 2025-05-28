# Integración con Webapp SaaS - InstallGuard v3.0

## Resumen

InstallGuard v3.0 incluye una nueva funcionalidad de integración completa con la webapp SaaS que permite el reporte automático de todas las aplicaciones instaladas en el sistema a una base de datos central para su gestión y aprobación.

## Arquitectura de la Integración

### Componentes Principales

1. **SoftwareReportingService**: Servicio principal que maneja la comunicación con la webapp
2. **InstallationMonitorService**: Modificado para incluir reporte automático
3. **API validate_software**: Endpoint de la webapp que recibe los datos
4. **Sistema de autenticación**: Basado en API Keys

### Flujo de Datos

```
Instalación Detectada → Recopilación de Datos → Análisis de Seguridad → Reporte a Webapp → Respuesta del Servidor
```

## Configuración

### appsettings.json

```json
{
  "SoftCheck": {
    "BaseUrl": "http://localhost:4002/api",
    "ApiKey": "305f98c40f6ab0224759d1725147ca1b"
  }
}
```

### Parámetros de Configuración

- **BaseUrl**: URL base de la API de la webapp SaaS
- **ApiKey**: Clave de autenticación para acceder a la API

## Datos Enviados

### Formato JSON del Payload

```json
{
  "device_id": "WIN-MACHINE-12345678",
  "user_id": "DOMAIN\\username",
  "software_name": "Nombre de la Aplicación",
  "version": "1.0.0",
  "vendor": "Editor de la Aplicación",
  "install_date": "2024-01-15T10:30:00Z",
  "install_path": "C:\\Program Files\\App",
  "install_method": "MSI",
  "last_executed": "2024-01-15T10:30:00Z",
  "is_running": false,
  "digital_signature": true,
  "is_approved": false,
  "detected_by": "windows_agent",
  "sha256": "abc123...",
  "notes": "Descripción: App; Arquitectura: x64; Tamaño: 50.2 MB"
}
```

### Campos Detallados

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `device_id` | string | Identificador único del dispositivo |
| `user_id` | string | Usuario que instaló la aplicación |
| `software_name` | string | Nombre de la aplicación |
| `version` | string | Versión de la aplicación |
| `vendor` | string | Editor/fabricante de la aplicación |
| `install_date` | string | Fecha de instalación (ISO 8601) |
| `install_path` | string | Ruta de instalación |
| `install_method` | string | Método de instalación (MSI, Setup, Manual) |
| `last_executed` | string | Última ejecución detectada |
| `is_running` | boolean | Si está ejecutándose actualmente |
| `digital_signature` | boolean | Si tiene firma digital válida |
| `is_approved` | boolean | Estado de aprobación (siempre false inicialmente) |
| `detected_by` | string | Identificador del agente ("windows_agent") |
| `sha256` | string | Hash SHA256 del ejecutable principal |
| `notes` | string | Información adicional concatenada |

## Generación de Device ID

El sistema genera un ID único para cada dispositivo usando la siguiente lógica:

1. **Método principal**: Número de serie de la placa base
   ```
   WIN-{SerialNumber}
   ```

2. **Método fallback**: Hash del nombre de máquina + usuario
   ```
   WIN-{MachineName}-{Hash8Chars}
   ```

## Autenticación

### API Key

- Se envía en el header `X-API-KEY`
- La webapp hashea la clave con SHA256 para comparación
- Se actualiza la fecha de último uso en cada request exitoso

### Headers HTTP

```
X-API-KEY: 305f98c40f6ab0224759d1725147ca1b
Accept: application/json
Content-Type: application/json
User-Agent: InstallGuard-Agent/2.0
```

## Respuesta de la Webapp

### Respuesta Exitosa

```json
{
  "success": true,
  "message": "Software registered successfully",
  "isApproved": false,
  "softwareId": "clxxxxx..."
}
```

### Respuesta de Error

```json
{
  "success": false,
  "message": "Error message",
  "error": "Detailed error information"
}
```

## Manejo de Errores

### Tipos de Error

1. **Error de conectividad**: Timeout o problemas de red
2. **Error de autenticación**: API Key inválida (401)
3. **Error de validación**: Datos faltantes o inválidos (400)
4. **Error del servidor**: Problemas internos de la webapp (500)

### Estrategia de Reintentos

- No se implementan reintentos automáticos
- Los errores se registran en el Event Log
- El servicio continúa funcionando normalmente

## Logging

### Niveles de Log

- **Information**: Reportes exitosos, conectividad confirmada
- **Warning**: Errores de reporte, problemas de conectividad
- **Error**: Errores críticos en el servicio de reporte
- **Debug**: Payloads JSON, respuestas del servidor

### Ejemplos de Logs

```
[INFO] Enviando datos de aplicación a webapp: Chrome v120.0.6099.109
[INFO] Aplicación reportada exitosamente: Chrome
[WARNING] No se pudo reportar instalación: Firefox
[ERROR] Error reportando instalación a webapp: Timeout
```

## Seguridad

### Datos Sensibles

- Las API Keys se almacenan en texto plano en appsettings.json
- No se envían datos personales del usuario más allá del nombre de usuario
- Los hashes SHA256 permiten verificación de integridad

### Consideraciones

- La comunicación se realiza por HTTP (no HTTPS en desarrollo)
- Se recomienda HTTPS para producción
- Las API Keys deben rotarse periódicamente

## Monitoreo y Diagnóstico

### Verificación de Conectividad

El servicio incluye un método `TestConnectivityAsync()` que verifica:
- Accesibilidad del endpoint `/health`
- Validez de la API Key
- Tiempo de respuesta del servidor

### Métricas Disponibles

- Número de aplicaciones reportadas exitosamente
- Número de errores de reporte
- Tiempo de respuesta promedio de la webapp
- Estado de aprobación de aplicaciones

## Integración con Sistema Existente

### Compatibilidad

- La funcionalidad de reporte es adicional y no afecta las funciones existentes
- El monitoreo de instalaciones continúa funcionando independientemente
- Las notificaciones al usuario no se ven afectadas

### Configuración Opcional

- El reporte a la webapp puede deshabilitarse modificando la configuración
- El sistema funciona completamente offline si la webapp no está disponible

## Casos de Uso

### Escenario 1: Instalación Nueva

1. Usuario instala una aplicación
2. InstallGuard detecta la instalación
3. Se recopilan todos los datos disponibles
4. Se envía reporte a la webapp
5. La webapp registra la aplicación como "pendiente de aprobación"
6. Se muestra notificación al usuario

### Escenario 2: Aplicación Existente

1. Se detecta una aplicación ya reportada
2. La webapp actualiza solo campos dinámicos (is_running, last_executed)
3. Se mantiene el estado de aprobación existente

### Escenario 3: Error de Conectividad

1. Se detecta una instalación
2. El reporte a la webapp falla
3. Se registra el error en logs
4. La notificación al usuario se muestra normalmente
5. El sistema continúa monitoreando

## Desarrollo y Testing

### Endpoints de Testing

- `GET /api/health`: Verificación de conectividad
- `POST /api/validate_software`: Reporte de aplicaciones

### Datos de Prueba

```json
{
  "device_id": "WIN-TEST-DEVICE",
  "user_id": "testuser",
  "software_name": "Test Application",
  "version": "1.0.0",
  "vendor": "Test Vendor",
  "install_date": "2024-01-15T10:30:00Z",
  "install_path": "C:\\Test\\App",
  "install_method": "Manual",
  "last_executed": "2024-01-15T10:30:00Z",
  "is_running": false,
  "digital_signature": false,
  "is_approved": false,
  "detected_by": "windows_agent",
  "sha256": "test_hash",
  "notes": "Test application for development"
}
```

## Roadmap Futuro

### Mejoras Planificadas

1. **Soporte HTTPS**: Comunicación segura con la webapp
2. **Reintentos automáticos**: Manejo inteligente de errores temporales
3. **Cache local**: Almacenamiento temporal para casos offline
4. **Compresión**: Reducción del tamaño de payloads
5. **Métricas avanzadas**: Dashboard de monitoreo en tiempo real

### Integraciones Adicionales

- Soporte para múltiples webapps
- Integración con sistemas de ticketing
- Alertas por email/Slack
- API para consulta de estado de aplicaciones 