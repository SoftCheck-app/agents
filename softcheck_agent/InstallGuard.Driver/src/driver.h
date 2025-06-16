/*++

Módulo:

    driver.h

Descripción:

    Declaraciones y definiciones principales para el controlador minifiltro 
    que intercepta y controla la instalación de aplicaciones en Windows.

--*/

#ifndef _INSTALLGUARD_DRIVER_H_
#define _INSTALLGUARD_DRIVER_H_

#include <fltKernel.h>
#include <dontuse.h>
#include <suppress.h>
#include <ntstrsafe.h>

//
// Definiciones y constantes
//

#define INSTALLGUARD_PORT_NAME                  L"\\InstallGuardPort"
#define INSTALLGUARD_MAX_CONNECTIONS            1
#define INSTALLGUARD_MAX_MESSAGE_SIZE           4096

// Extensiones de archivos a interceptar
#define INSTALLGUARD_EXE_EXTENSION              L"exe"
#define INSTALLGUARD_MSI_EXTENSION              L"msi"
#define INSTALLGUARD_APPX_EXTENSION             L"appx"
#define INSTALLGUARD_MSIX_EXTENSION             L"msix"

// Códigos de comando para comunicación con el servicio de usuario
#define INSTALLGUARD_CMD_INSTALL_REQUEST        0x1001
#define INSTALLGUARD_CMD_INSTALL_RESPONSE       0x1002
#define INSTALLGUARD_CMD_CLEANUP_REQUEST        0x1003

//
// Estructuras de datos para la comunicación
//

// Estructura para el mensaje enviado al servicio de usuario
typedef struct _INSTALLGUARD_MESSAGE {
    ULONG CommandCode;             // Código de comando
    ULONG Size;                    // Tamaño total del mensaje
    WCHAR FilePath[1024];          // Ruta del archivo
    LONGLONG FileSize;             // Tamaño del archivo
    ULONG ProcessId;               // ID del proceso que realiza la operación
    WCHAR ProcessName[256];        // Nombre del proceso
    WCHAR Username[256];           // Nombre del usuario
    LONGLONG Timestamp;            // Marca de tiempo de la operación
} INSTALLGUARD_MESSAGE, *PINSTALLGUARD_MESSAGE;

// Estructura para la respuesta del servicio de usuario
typedef struct _INSTALLGUARD_RESPONSE {
    ULONG CommandCode;             // Código de comando
    ULONG RequestId;               // ID de la solicitud original 
    BOOLEAN AllowInstallation;     // TRUE si se permite la instalación, FALSE en caso contrario
    WCHAR Reason[512];             // Razón (para registro/auditoría)
} INSTALLGUARD_RESPONSE, *PINSTALLGUARD_RESPONSE;

//
// Estructuras de contexto
//

// Contexto de instancia para el minifiltro
typedef struct _INSTALLGUARD_INSTANCE_CONTEXT {
    PFLT_INSTANCE Instance;
    UNICODE_STRING VolumeName;
} INSTALLGUARD_INSTANCE_CONTEXT, *PINSTALLGUARD_INSTANCE_CONTEXT;

// Contexto de la solicitud de instalación pendiente
typedef struct _INSTALLGUARD_PENDING_CONTEXT {
    LIST_ENTRY ListEntry;
    LONGLONG RequestId;
    PFLT_CALLBACK_DATA Data;
    BOOLEAN IsInstallationAllowed;
    LARGE_INTEGER CreationTime;
} INSTALLGUARD_PENDING_CONTEXT, *PINSTALLGUARD_PENDING_CONTEXT;

//
// Prototipos de funciones globales
//

NTSTATUS
DriverEntry(
    _In_ PDRIVER_OBJECT DriverObject,
    _In_ PUNICODE_STRING RegistryPath
);

NTSTATUS
InstallGuardUnload(
    _In_ FLT_FILTER_UNLOAD_FLAGS Flags
);

NTSTATUS
InstallGuardInstanceSetup(
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ FLT_INSTANCE_SETUP_FLAGS Flags,
    _In_ DEVICE_TYPE VolumeDeviceType,
    _In_ FLT_FILESYSTEM_TYPE VolumeFilesystemType
);

VOID
InstallGuardInstanceTeardownStart(
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ FLT_INSTANCE_TEARDOWN_FLAGS Flags
);

VOID
InstallGuardInstanceTeardownComplete(
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ FLT_INSTANCE_TEARDOWN_FLAGS Flags
);

// Variables globales
extern PFLT_FILTER gFilterHandle;
extern PFLT_PORT gServerPort;
extern PFLT_PORT gClientPort;
extern ERESOURCE gPendingRequestsLock;
extern LIST_ENTRY gPendingRequestsList;

#endif // _INSTALLGUARD_DRIVER_H_ 