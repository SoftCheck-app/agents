# InstallGuard v3.0 FINAL - Paquete de Distribucion 
 
## Opciones de Instalacion 
 
### 1. Instalacion Portable (Recomendado para distribucion masiva) 
- Ejecutar: `install-portable-autostart.bat` como administrador 
- Se instala en: `C:\InstallGuard\` 
- Auto-inicio configurado automaticamente 
- Facil de distribuir via USB, red compartida, etc. 
 
### 2. Instalacion como Servicio de Windows 
- Ejecutar: `install-as-service.bat` como administrador 
- Se instala en: `C:\Program Files\InstallGuard\` 
- Ejecuta como servicio del sistema 
 
## Desinstalacion 
- Para version portable: `uninstall-portable.bat` 
- Para servicio: usar Panel de Control o `sc delete InstallGuard` 
 
## Configuracion 
- Editar `appsettings.json` para cambiar URL de la webapp 
- Por defecto apunta a: `http://localhost:4002/api` 
