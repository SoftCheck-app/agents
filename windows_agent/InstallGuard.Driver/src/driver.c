/*++

Módulo:

    driver.c

Descripción:

    Implementación de las funciones principales del controlador minifiltro
    que intercepta y controla la instalación de aplicaciones en Windows.

--*/

#include "driver.h"
#include "filter.h"
#include "communication.h"
#include "notification.h"

// Variables globales
PFLT_FILTER gFilterHandle = NULL;
PFLT_PORT gServerPort = NULL;
PFLT_PORT gClientPort = NULL;
ERESOURCE gPendingRequestsLock;
LIST_ENTRY gPendingRequestsList;

// Arreglo de las operaciones a interceptar
CONST FLT_OPERATION_REGISTRATION Callbacks[] = {
    { IRP_MJ_CREATE,
      0,
      InstallGuardPreCreate,
      InstallGuardPostCreate },

    { IRP_MJ_WRITE,
      0,
      InstallGuardPreWrite,
      NULL },

    { IRP_MJ_SET_INFORMATION,
      0,
      InstallGuardPreSetInformation,
      NULL },

    { IRP_MJ_OPERATION_END }
};

// Estructura de registro del minifiltro
CONST FLT_REGISTRATION FilterRegistration = {
    sizeof(FLT_REGISTRATION),                     // Tamaño
    FLT_REGISTRATION_VERSION,                     // Versión
    0,                                            // Flags
    NULL,                                         // Contexto
    Callbacks,                                    // Callback de operaciones
    InstallGuardUnload,                           // Rutina de descarga del filtro
    InstallGuardInstanceSetup,                    // Callback de configuración de instancia
    InstallGuardInstanceTeardownStart,            // Callback de inicio de desmantelamiento de instancia
    InstallGuardInstanceTeardownComplete,         // Callback de fin de desmantelamiento de instancia
    NULL,                                         // NameProvider
    NULL,                                         // SectionNotificationCallback
    NULL,                                         // TransactionNotificationCallback
    NULL                                          // NormalizeContextCallback
};

/*++

Rutina:

    DriverEntry

Descripción:

    Punto de entrada principal del controlador. Inicializa el minifiltro y
    configura la comunicación con el servicio en modo usuario.

Argumentos:

    DriverObject - Puntero al objeto del controlador
    RegistryPath - Puntero a la ruta del registro para este controlador

Valor devuelto:

    STATUS_SUCCESS si la inicialización fue exitosa, o un código de error NTSTATUS.

--*/
NTSTATUS
DriverEntry(
    _In_ PDRIVER_OBJECT DriverObject,
    _In_ PUNICODE_STRING RegistryPath
)
{
    NTSTATUS status;

    UNREFERENCED_PARAMETER(RegistryPath);

    LOG_INFO(TRACE_INIT, "InstallGuard: Iniciando el controlador...");

    // Inicializar la lista de solicitudes pendientes
    ExInitializeResourceLite(&gPendingRequestsLock);
    InitializeListHead(&gPendingRequestsList);

    // Registrar el minifiltro
    status = FltRegisterFilter(
        DriverObject,
        &FilterRegistration,
        &gFilterHandle
    );

    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_INIT, "InstallGuard: Error al registrar el filtro. Status: 0x%08X", status);
        return status;
    }

    // Inicializar la comunicación con el servicio en modo usuario
    status = InstallGuardInitializePortCommunication(gFilterHandle);

    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_INIT, "InstallGuard: Error al inicializar la comunicación con el puerto. Status: 0x%08X", status);
        FltUnregisterFilter(gFilterHandle);
        return status;
    }

    // Iniciar el filtrado
    status = FltStartFiltering(gFilterHandle);

    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_INIT, "InstallGuard: Error al iniciar el filtrado. Status: 0x%08X", status);
        InstallGuardClosePortCommunication();
        FltUnregisterFilter(gFilterHandle);
        return status;
    }

    LOG_INFO(TRACE_INIT, "InstallGuard: Controlador iniciado correctamente");

    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardUnload

Descripción:

    Rutina de descarga del controlador minifiltro. Libera los recursos utilizados.

Argumentos:

    Flags - Flags para la descarga del filtro

Valor devuelto:

    STATUS_SUCCESS si la descarga fue exitosa, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardUnload(
    _In_ FLT_FILTER_UNLOAD_FLAGS Flags
)
{
    UNREFERENCED_PARAMETER(Flags);

    LOG_INFO(TRACE_INIT, "InstallGuard: Descargando el controlador...");

    // Cerrar el puerto de comunicación
    InstallGuardClosePortCommunication();

    // Limpiar la lista de solicitudes pendientes
    InstallGuardCleanupPendingRequests(TRUE);

    // Liberar el recurso de bloqueo
    ExDeleteResourceLite(&gPendingRequestsLock);

    // Anular el registro del filtro
    FltUnregisterFilter(gFilterHandle);

    LOG_INFO(TRACE_INIT, "InstallGuard: Controlador descargado correctamente");

    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardInstanceSetup

Descripción:

    Rutina de configuración de instancia del minifiltro. Determina si el
    controlador debe adjuntarse a un volumen específico.

Argumentos:

    FltObjects - Puntero a los objetos asociados a la instancia
    Flags - Flags de configuración
    VolumeDeviceType - Tipo de dispositivo del volumen
    VolumeFilesystemType - Tipo de sistema de archivos del volumen

Valor devuelto:

    STATUS_SUCCESS si la configuración fue exitosa, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardInstanceSetup(
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ FLT_INSTANCE_SETUP_FLAGS Flags,
    _In_ DEVICE_TYPE VolumeDeviceType,
    _In_ FLT_FILESYSTEM_TYPE VolumeFilesystemType
)
{
    UNREFERENCED_PARAMETER(Flags);
    UNREFERENCED_PARAMETER(FltObjects);

    LOG_INFO(TRACE_INIT, "InstallGuard: Configurando instancia para un nuevo volumen");

    // No nos adjuntamos a sistemas de archivos de red
    if (VolumeDeviceType == FILE_DEVICE_NETWORK_FILE_SYSTEM) {
        LOG_INFO(TRACE_INIT, "InstallGuard: Omitiendo instancia en sistema de archivos de red");
        return STATUS_FLT_DO_NOT_ATTACH;
    }

    // Sólo nos interesa NTFS, FAT, exFAT y ReFS
    switch (VolumeFilesystemType) {
    case FLT_FSTYPE_NTFS:
    case FLT_FSTYPE_FAT:
    case FLT_FSTYPE_EXFAT:
    case FLT_FSTYPE_REFS:
        LOG_INFO(TRACE_INIT, "InstallGuard: Adjuntando instancia a sistema de archivos compatible");
        return STATUS_SUCCESS;

    default:
        LOG_INFO(TRACE_INIT, "InstallGuard: Omitiendo instancia en sistema de archivos no compatible: %d", VolumeFilesystemType);
        return STATUS_FLT_DO_NOT_ATTACH;
    }
}

/*++

Rutina:

    InstallGuardInstanceTeardownStart

Descripción:

    Rutina llamada cuando comienza el desmantelamiento de una instancia.

Argumentos:

    FltObjects - Puntero a los objetos asociados a la instancia
    Flags - Flags de desmantelamiento

Valor devuelto:

    Ninguno

--*/
VOID
InstallGuardInstanceTeardownStart(
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ FLT_INSTANCE_TEARDOWN_FLAGS Flags
)
{
    UNREFERENCED_PARAMETER(FltObjects);
    UNREFERENCED_PARAMETER(Flags);

    LOG_INFO(TRACE_INIT, "InstallGuard: Iniciando desmantelamiento de instancia");
}

/*++

Rutina:

    InstallGuardInstanceTeardownComplete

Descripción:

    Rutina llamada cuando se completa el desmantelamiento de una instancia.

Argumentos:

    FltObjects - Puntero a los objetos asociados a la instancia
    Flags - Flags de desmantelamiento

Valor devuelto:

    Ninguno

--*/
VOID
InstallGuardInstanceTeardownComplete(
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ FLT_INSTANCE_TEARDOWN_FLAGS Flags
)
{
    UNREFERENCED_PARAMETER(FltObjects);
    UNREFERENCED_PARAMETER(Flags);

    LOG_INFO(TRACE_INIT, "InstallGuard: Completado desmantelamiento de instancia");
} 