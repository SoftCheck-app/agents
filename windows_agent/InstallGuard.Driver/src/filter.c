/*++

Módulo:

    filter.c

Descripción:

    Implementación de las funciones de filtrado de archivos del controlador
    minifiltro InstallGuard.

--*/

#include "filter.h"
#include "notification.h"

/*++

Rutina:

    InstallGuardPreCreate

Descripción:

    Rutina de callback previa a la operación CREATE. Se llama cuando un proceso
    intenta abrir o crear un archivo.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    FltObjects - Puntero a los objetos relacionados con el filtro
    CompletionContext - Contexto de finalización a pasar a la rutina post-operación

Valor devuelto:

    FLT_PREOP_SUCCESS_WITH_CALLBACK - La operación debe continuar con una llamada a la rutina post-operación
    FLT_PREOP_SUCCESS_NO_CALLBACK - La operación debe continuar sin llamada a la rutina post-operación

--*/
FLT_PREOP_CALLBACK_STATUS
InstallGuardPreCreate(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Flt_CompletionContext_Outptr_ PVOID* CompletionContext
)
{
    UNREFERENCED_PARAMETER(CompletionContext);

    PFLT_FILE_NAME_INFORMATION nameInfo = NULL;
    NTSTATUS status;
    BOOLEAN isInstallerFile = FALSE;

    // No nos interesan operaciones de kernel o directorios
    if (FltObjects->FileObject == NULL || 
        Data->RequestorMode == KernelMode || 
        FlagOn(Data->Iopb->OperationFlags, SL_OPEN_TARGET_DIRECTORY)) {
        return FLT_PREOP_SUCCESS_NO_CALLBACK;
    }

    // Verificar si el acceso es para crear/modificar archivos (no solo lectura)
    if (!(Data->Iopb->Parameters.Create.SecurityContext->DesiredAccess & 
          (FILE_WRITE_DATA | FILE_APPEND_DATA | GENERIC_WRITE | GENERIC_ALL))) {
        return FLT_PREOP_SUCCESS_NO_CALLBACK;
    }

    // Si es un archivo instalador, verificamos si deberíamos monitorearlo
    if (NT_SUCCESS(InstallGuardGetFileNameInformation(Data, FltObjects, &nameInfo))) {
        if (nameInfo->Extension.Length > 0) {
            isInstallerFile = InstallGuardCheckFileExtension(&nameInfo->Extension);
        }
        FltReleaseFileNameInformation(nameInfo);
    }

    // Si no es un archivo instalador, permitir la operación sin callback
    if (!isInstallerFile) {
        return FLT_PREOP_SUCCESS_NO_CALLBACK;
    }

    // Si llegamos aquí, es un archivo instalador potencial
    // Permitir la creación, pero monitorear en el callback de post-operación
    return FLT_PREOP_SUCCESS_WITH_CALLBACK;
}

/*++

Rutina:

    InstallGuardPostCreate

Descripción:

    Rutina de callback posterior a la operación CREATE. Se llama cuando un proceso
    ha abierto o creado un archivo instalador.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    FltObjects - Puntero a los objetos relacionados con el filtro
    CompletionContext - Contexto de finalización de la rutina pre-operación
    Flags - Flags de la operación post

Valor devuelto:

    FLT_POSTOP_FINISHED_PROCESSING - Hemos terminado de procesar la operación

--*/
FLT_POSTOP_CALLBACK_STATUS
InstallGuardPostCreate(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_opt_ PVOID CompletionContext,
    _In_ FLT_POST_OPERATION_FLAGS Flags
)
{
    UNREFERENCED_PARAMETER(CompletionContext);
    UNREFERENCED_PARAMETER(Flags);

    NTSTATUS status;
    PFLT_FILE_NAME_INFORMATION nameInfo = NULL;
    
    // Solo nos interesan las operaciones exitosas
    if (!NT_SUCCESS(Data->IoStatus.Status) || (Data->IoStatus.Status == STATUS_REPARSE)) {
        return FLT_POSTOP_FINISHED_PROCESSING;
    }

    // Obtener información del nombre del archivo
    status = InstallGuardGetFileNameInformation(Data, FltObjects, &nameInfo);
    if (!NT_SUCCESS(status)) {
        return FLT_POSTOP_FINISHED_PROCESSING;
    }

    // Verificar si es un instalador y notificar al servicio
    if (InstallGuardCheckFileExtension(&nameInfo->Extension)) {
        LOG_INFO(TRACE_FILTER, "InstallGuard: Detectado acceso a instalador: %wZ", &nameInfo->Name);
        
        // Notificar intento de instalación
        status = InstallGuardNotifyInstallationAttempt(Data, FltObjects, &nameInfo->Name);
        if (!NT_SUCCESS(status)) {
            LOG_ERROR(TRACE_FILTER, "InstallGuard: Error al notificar intento de instalación: 0x%08X", status);
        }
    }

    FltReleaseFileNameInformation(nameInfo);
    return FLT_POSTOP_FINISHED_PROCESSING;
}

/*++

Rutina:

    InstallGuardPreWrite

Descripción:

    Rutina de callback previa a la operación WRITE. Se llama cuando un proceso
    intenta escribir en un archivo.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    FltObjects - Puntero a los objetos relacionados con el filtro
    CompletionContext - Contexto de finalización a pasar a la rutina post-operación

Valor devuelto:

    FLT_PREOP_SUCCESS_NO_CALLBACK - La operación debe continuar sin llamada a la rutina post-operación
    FLT_PREOP_PENDING - La operación está pendiente de aprobación
    FLT_PREOP_COMPLETE - La operación se completa con el estado devuelto

--*/
FLT_PREOP_CALLBACK_STATUS
InstallGuardPreWrite(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Flt_CompletionContext_Outptr_ PVOID* CompletionContext
)
{
    UNREFERENCED_PARAMETER(CompletionContext);

    // Solo nos interesan operaciones en modo usuario
    if (Data->RequestorMode == KernelMode) {
        return FLT_PREOP_SUCCESS_NO_CALLBACK;
    }

    // Verificar si es un instalador
    if (InstallGuardIsInstallerFile(Data, FltObjects)) {
        PFLT_FILE_NAME_INFORMATION nameInfo = NULL;
        NTSTATUS status;

        // Obtener información del nombre del archivo
        status = InstallGuardGetFileNameInformation(Data, FltObjects, &nameInfo);
        if (NT_SUCCESS(status)) {
            // Notificar intento de instalación
            status = InstallGuardNotifyInstallationAttempt(Data, FltObjects, &nameInfo->Name);
            FltReleaseFileNameInformation(nameInfo);

            if (NT_SUCCESS(status)) {
                // Si la notificación fue exitosa, la operación está pendiente
                // El servicio determinará si se permite o no
                return FLT_PREOP_PENDING;
            }
        }
    }

    // Si no es un instalador o no pudimos notificar, permitir la operación
    return FLT_PREOP_SUCCESS_NO_CALLBACK;
}

/*++

Rutina:

    InstallGuardPreSetInformation

Descripción:

    Rutina de callback previa a la operación SET_INFORMATION. Se llama cuando un proceso
    intenta modificar atributos o renombrar un archivo.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    FltObjects - Puntero a los objetos relacionados con el filtro
    CompletionContext - Contexto de finalización a pasar a la rutina post-operación

Valor devuelto:

    FLT_PREOP_SUCCESS_NO_CALLBACK - La operación debe continuar sin llamada a la rutina post-operación
    FLT_PREOP_PENDING - La operación está pendiente de aprobación
    FLT_PREOP_COMPLETE - La operación se completa con el estado devuelto

--*/
FLT_PREOP_CALLBACK_STATUS
InstallGuardPreSetInformation(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Flt_CompletionContext_Outptr_ PVOID* CompletionContext
)
{
    UNREFERENCED_PARAMETER(CompletionContext);

    // Solo nos interesan operaciones en modo usuario
    if (Data->RequestorMode == KernelMode) {
        return FLT_PREOP_SUCCESS_NO_CALLBACK;
    }

    // Solo nos interesan cambios de nombre y eliminación
    FILE_INFORMATION_CLASS fileInfoClass = Data->Iopb->Parameters.SetFileInformation.FileInformationClass;
    if (fileInfoClass != FileDispositionInformation && 
        fileInfoClass != FileDispositionInformationEx &&
        fileInfoClass != FileRenameInformation) {
        return FLT_PREOP_SUCCESS_NO_CALLBACK;
    }

    // Verificar si es un archivo instalador
    if (InstallGuardIsInstallerFile(Data, FltObjects)) {
        PFLT_FILE_NAME_INFORMATION nameInfo = NULL;
        NTSTATUS status;

        // Obtener información del nombre del archivo
        status = InstallGuardGetFileNameInformation(Data, FltObjects, &nameInfo);
        if (NT_SUCCESS(status)) {
            // Si es una operación de eliminación, permitirla ya que puede ser parte
            // del proceso de limpieza de una instalación denegada
            if (fileInfoClass == FileDispositionInformation || 
                fileInfoClass == FileDispositionInformationEx) {
                // Permitir eliminación sin más verificaciones
                FltReleaseFileNameInformation(nameInfo);
                return FLT_PREOP_SUCCESS_NO_CALLBACK;
            }

            // Para cambios de nombre, notificar como intento de instalación
            status = InstallGuardNotifyInstallationAttempt(Data, FltObjects, &nameInfo->Name);
            FltReleaseFileNameInformation(nameInfo);

            if (NT_SUCCESS(status)) {
                return FLT_PREOP_PENDING;
            }
        }
    }

    return FLT_PREOP_SUCCESS_NO_CALLBACK;
}

/*++

Rutina:

    InstallGuardIsInstallerFile

Descripción:

    Determina si un archivo es un instalador basado en su extensión.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    FltObjects - Puntero a los objetos relacionados con el filtro

Valor devuelto:

    TRUE si el archivo es un instalador, FALSE en caso contrario

--*/
BOOLEAN
InstallGuardIsInstallerFile(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects
)
{
    PFLT_FILE_NAME_INFORMATION nameInfo = NULL;
    NTSTATUS status;
    BOOLEAN result = FALSE;

    // Obtener información del nombre del archivo
    status = InstallGuardGetFileNameInformation(Data, FltObjects, &nameInfo);
    if (!NT_SUCCESS(status)) {
        return FALSE;
    }

    // Verificar extensión
    if (nameInfo->Extension.Length > 0) {
        result = InstallGuardCheckFileExtension(&nameInfo->Extension);
    }

    FltReleaseFileNameInformation(nameInfo);
    return result;
}

/*++

Rutina:

    InstallGuardGetFileNameInformation

Descripción:

    Obtiene información del nombre del archivo para una operación.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    FltObjects - Puntero a los objetos relacionados con el filtro
    NameInfo - Dirección de un puntero que recibirá la información del nombre

Valor devuelto:

    STATUS_SUCCESS si la información se obtuvo correctamente, o un código
    de error NTSTATUS en caso contrario.

--*/
NTSTATUS
InstallGuardGetFileNameInformation(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Out_ PFLT_FILE_NAME_INFORMATION* NameInfo
)
{
    NTSTATUS status;
    PFLT_FILE_NAME_INFORMATION nameInfo = NULL;

    // Intentar obtener la ruta normalizada
    status = FltGetFileNameInformation(
        Data,
        FLT_FILE_NAME_NORMALIZED | FLT_FILE_NAME_QUERY_DEFAULT,
        &nameInfo
    );

    if (!NT_SUCCESS(status)) {
        // Si falla, intentar con la ruta abierta
        status = FltGetFileNameInformation(
            Data,
            FLT_FILE_NAME_OPENED | FLT_FILE_NAME_QUERY_DEFAULT,
            &nameInfo
        );

        if (!NT_SUCCESS(status)) {
            return status;
        }
    }

    status = FltParseFileNameInformation(nameInfo);
    if (!NT_SUCCESS(status)) {
        FltReleaseFileNameInformation(nameInfo);
        return status;
    }

    *NameInfo = nameInfo;
    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardCheckFileExtension

Descripción:

    Verifica si la extensión del archivo corresponde a un instalador.

Argumentos:

    Extension - Puntero a la estructura UNICODE_STRING que contiene la extensión

Valor devuelto:

    TRUE si la extensión corresponde a un instalador, FALSE en caso contrario

--*/
BOOLEAN
InstallGuardCheckFileExtension(
    _In_ PCUNICODE_STRING Extension
)
{
    static const UNICODE_STRING exeExt = RTL_CONSTANT_STRING(L".exe");
    static const UNICODE_STRING msiExt = RTL_CONSTANT_STRING(L".msi");
    static const UNICODE_STRING appxExt = RTL_CONSTANT_STRING(L".appx");
    static const UNICODE_STRING msixExt = RTL_CONSTANT_STRING(L".msix");

    // Comparar con extensiones conocidas
    if (FsRtlIsNameInExpression(&exeExt, Extension, TRUE, NULL) ||
        FsRtlIsNameInExpression(&msiExt, Extension, TRUE, NULL) ||
        FsRtlIsNameInExpression(&appxExt, Extension, TRUE, NULL) ||
        FsRtlIsNameInExpression(&msixExt, Extension, TRUE, NULL)) {
        return TRUE;
    }

    return FALSE;
}

/*++

Rutina:

    InstallGuardAddPendingRequest

Descripción:

    Agrega una solicitud a la lista de solicitudes pendientes.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    RequestId - ID de la solicitud

Valor devuelto:

    STATUS_SUCCESS si la solicitud se agregó correctamente, o un código
    de error NTSTATUS en caso contrario.

--*/
NTSTATUS
InstallGuardAddPendingRequest(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ LONGLONG RequestId
)
{
    NTSTATUS status = STATUS_SUCCESS;
    PINSTALLGUARD_PENDING_CONTEXT pendingContext;

    // Alocar memoria para el contexto
    pendingContext = ExAllocatePoolWithTag(NonPagedPool, sizeof(INSTALLGUARD_PENDING_CONTEXT), 'dGsI');
    if (pendingContext == NULL) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }

    // Inicializar contexto
    pendingContext->RequestId = RequestId;
    pendingContext->Data = Data;
    pendingContext->IsInstallationAllowed = FALSE;
    KeQuerySystemTime(&pendingContext->CreationTime);

    // Adquirir el bloqueo de recursos
    ExAcquireResourceExclusiveLite(&gPendingRequestsLock, TRUE);

    // Referencia la estructura Data para que no se libere mientras está pendiente
    FltReferenceOperationContext(Data);

    // Insertar en la lista
    InsertTailList(&gPendingRequestsList, &pendingContext->ListEntry);

    // Liberar el bloqueo
    ExReleaseResourceLite(&gPendingRequestsLock);

    LOG_INFO(TRACE_FILTER, "InstallGuard: Agregada solicitud pendiente ID %lld", RequestId);
    
    return status;
}

/*++

Rutina:

    InstallGuardFindAndRemovePendingRequest

Descripción:

    Busca y elimina una solicitud pendiente por su ID.

Argumentos:

    RequestId - ID de la solicitud a buscar
    Data - Dirección de un puntero que recibirá la estructura de datos asociada
    AllowInstallation - Dirección de un booleano que recibirá si la instalación está permitida

Valor devuelto:

    STATUS_SUCCESS si la solicitud se encontró y eliminó correctamente, o
    STATUS_NOT_FOUND si la solicitud no se encontró.

--*/
NTSTATUS
InstallGuardFindAndRemovePendingRequest(
    _In_ LONGLONG RequestId,
    _Out_ PFLT_CALLBACK_DATA* Data,
    _Out_ PBOOLEAN AllowInstallation
)
{
    NTSTATUS status = STATUS_NOT_FOUND;
    PLIST_ENTRY entry;
    PINSTALLGUARD_PENDING_CONTEXT pendingContext = NULL;

    // Adquirir el bloqueo de recursos
    ExAcquireResourceExclusiveLite(&gPendingRequestsLock, TRUE);

    // Buscar la solicitud en la lista
    for (entry = gPendingRequestsList.Flink; entry != &gPendingRequestsList; entry = entry->Flink) {
        pendingContext = CONTAINING_RECORD(entry, INSTALLGUARD_PENDING_CONTEXT, ListEntry);
        if (pendingContext->RequestId == RequestId) {
            // Encontrada, eliminar de la lista
            RemoveEntryList(&pendingContext->ListEntry);
            status = STATUS_SUCCESS;
            break;
        }
    }

    // Liberar el bloqueo
    ExReleaseResourceLite(&gPendingRequestsLock);

    if (NT_SUCCESS(status)) {
        // Devolver datos y liberar contexto
        *Data = pendingContext->Data;
        *AllowInstallation = pendingContext->IsInstallationAllowed;
        ExFreePoolWithTag(pendingContext, 'dGsI');
        LOG_INFO(TRACE_FILTER, "InstallGuard: Eliminada solicitud pendiente ID %lld", RequestId);
    }

    return status;
}

/*++

Rutina:

    InstallGuardCleanupPendingRequests

Descripción:

    Limpia las solicitudes pendientes antiguas o todas si se especifica.

Argumentos:

    ForceCleanAll - TRUE para limpiar todas las solicitudes, FALSE para limpiar solo las antiguas

Valor devuelto:

    Ninguno

--*/
void
InstallGuardCleanupPendingRequests(
    _In_ BOOLEAN ForceCleanAll
)
{
    PLIST_ENTRY entry, nextEntry;
    PINSTALLGUARD_PENDING_CONTEXT pendingContext;
    LARGE_INTEGER currentTime;
    LARGE_INTEGER timeout;

    // Obtener tiempo actual
    KeQuerySystemTime(&currentTime);
    timeout.QuadPart = INSTALLGUARD_NOTIFICATION_TIMEOUT;

    // Adquirir el bloqueo de recursos
    ExAcquireResourceExclusiveLite(&gPendingRequestsLock, TRUE);

    // Recorrer la lista
    for (entry = gPendingRequestsList.Flink; entry != &gPendingRequestsList; entry = nextEntry) {
        nextEntry = entry->Flink;
        pendingContext = CONTAINING_RECORD(entry, INSTALLGUARD_PENDING_CONTEXT, ListEntry);

        // Limpiar si se fuerza o si ha expirado el tiempo de espera
        if (ForceCleanAll || (currentTime.QuadPart - pendingContext->CreationTime.QuadPart > timeout.QuadPart)) {
            // Eliminar de la lista
            RemoveEntryList(&pendingContext->ListEntry);

            // Rechazar la operación por tiempo de espera
            if (!ForceCleanAll) {
                InstallGuardCompleteOperation(pendingContext->Data, BlockStateTimedOut);
            }

            // Liberar la referencia
            FltDereferenceOperationContext(pendingContext->Data);

            // Liberar memoria
            ExFreePoolWithTag(pendingContext, 'dGsI');
        }
    }

    // Liberar el bloqueo
    ExReleaseResourceLite(&gPendingRequestsLock);
} 