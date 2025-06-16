/*++

Módulo:

    notification.c

Descripción:

    Implementación de las funciones de notificación generadas
    por el controlador minifiltro InstallGuard.

--*/

#include "notification.h"
#include "communication.h"

// Contador para IDs de solicitud
static LONGLONG gRequestIdCounter = 0;

/*++

Rutina:

    InstallGuardNotifyInstallationAttempt

Descripción:

    Notifica un intento de instalación de aplicación al servicio en modo usuario.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    FltObjects - Puntero a los objetos relacionados con el filtro
    FilePath - Puntero a la ruta del archivo

Valor devuelto:

    STATUS_SUCCESS si la notificación fue exitosa, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardNotifyInstallationAttempt(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ PCUNICODE_STRING FilePath
)
{
    NTSTATUS status;
    INSTALLGUARD_MESSAGE message;
    LONGLONG requestId;
    UNICODE_STRING processName = { 0 };
    UNICODE_STRING username = { 0 };
    LONGLONG fileSize = 0;
    LARGE_INTEGER currentTime;

    // Si no hay cliente conectado, no podemos enviar notificación
    if (gClientPort == NULL) {
        LOG_WARNING(TRACE_NOTIFICATION, "InstallGuard: No hay cliente conectado para notificar instalación");
        return STATUS_PORT_DISCONNECTED;
    }

    LOG_INFO(TRACE_NOTIFICATION, "InstallGuard: Notificando intento de instalación: %wZ", FilePath);

    // Generar ID único para esta solicitud
    requestId = InterlockedIncrement64(&gRequestIdCounter);

    // Obtener información adicional
    InstallGuardGetProcessName(PsGetCurrentProcessId(), &processName);
    InstallGuardGetCurrentUsername(&username);
    InstallGuardGetFileSize(FltObjects->Instance, FltObjects->FileObject, &fileSize);
    KeQuerySystemTime(&currentTime);

    // Inicializar estructura de mensaje
    RtlZeroMemory(&message, sizeof(message));
    message.CommandCode = INSTALLGUARD_CMD_INSTALL_REQUEST;
    message.Size = sizeof(message);
    message.ProcessId = HandleToULong(PsGetCurrentProcessId());
    message.FileSize = fileSize;
    message.Timestamp = currentTime.QuadPart;

    // Copiar ruta del archivo
    if (FilePath->Length < sizeof(message.FilePath)) {
        RtlCopyMemory(message.FilePath, FilePath->Buffer, FilePath->Length);
        message.FilePath[FilePath->Length / sizeof(WCHAR)] = L'\0';
    }
    else {
        // Truncar nombre si es demasiado largo
        RtlCopyMemory(message.FilePath, FilePath->Buffer, sizeof(message.FilePath) - sizeof(WCHAR));
        message.FilePath[(sizeof(message.FilePath) / sizeof(WCHAR)) - 1] = L'\0';
    }

    // Copiar nombre del proceso
    if (processName.Length < sizeof(message.ProcessName)) {
        RtlCopyMemory(message.ProcessName, processName.Buffer, processName.Length);
        message.ProcessName[processName.Length / sizeof(WCHAR)] = L'\0';
    }
    else {
        // Truncar nombre si es demasiado largo
        RtlCopyMemory(message.ProcessName, processName.Buffer, sizeof(message.ProcessName) - sizeof(WCHAR));
        message.ProcessName[(sizeof(message.ProcessName) / sizeof(WCHAR)) - 1] = L'\0';
    }

    // Copiar nombre de usuario
    if (username.Length < sizeof(message.Username)) {
        RtlCopyMemory(message.Username, username.Buffer, username.Length);
        message.Username[username.Length / sizeof(WCHAR)] = L'\0';
    }
    else {
        // Truncar nombre si es demasiado largo
        RtlCopyMemory(message.Username, username.Buffer, sizeof(message.Username) - sizeof(WCHAR));
        message.Username[(sizeof(message.Username) / sizeof(WCHAR)) - 1] = L'\0';
    }

    // Agregar solicitud a la lista de pendientes
    status = InstallGuardAddPendingRequest(Data, requestId);
    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_NOTIFICATION, "InstallGuard: Error al agregar solicitud pendiente: 0x%08X", status);
        return status;
    }

    // Enviar mensaje al servicio
    status = InstallGuardSendMessageToService(&message);
    if (!NT_SUCCESS(status)) {
        // Si falla el envío, completar la operación para evitar bloqueos
        InstallGuardCompleteOperation(Data, BlockStateTimedOut);
        return status;
    }

    LOG_INFO(TRACE_NOTIFICATION, "InstallGuard: Intento de instalación notificado con ID: %lld", requestId);
    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardProcessInstallationResponse

Descripción:

    Procesa la respuesta a un intento de instalación de aplicación.

Argumentos:

    RequestId - ID de la solicitud
    AllowInstallation - TRUE si se permite la instalación, FALSE en caso contrario
    Reason - Razón de la decisión (para registro/auditoría)

Valor devuelto:

    STATUS_SUCCESS si la respuesta fue procesada correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardProcessInstallationResponse(
    _In_ LONGLONG RequestId,
    _In_ BOOLEAN AllowInstallation,
    _In_opt_ PCWSTR Reason
)
{
    NTSTATUS status;
    PFLT_CALLBACK_DATA data = NULL;
    BOOLEAN allowState = FALSE;
    INSTALLGUARD_BLOCK_STATE blockState;

    LOG_INFO(TRACE_NOTIFICATION, 
        "InstallGuard: Procesando respuesta para solicitud ID %lld: %s", 
        RequestId, 
        AllowInstallation ? "Permitida" : "Denegada"
    );

    if (Reason != NULL) {
        LOG_INFO(TRACE_NOTIFICATION, "InstallGuard: Razón: %ws", Reason);
    }

    // Buscar y eliminar la solicitud pendiente
    status = InstallGuardFindAndRemovePendingRequest(RequestId, &data, &allowState);
    if (!NT_SUCCESS(status)) {
        LOG_WARNING(TRACE_NOTIFICATION, "InstallGuard: Solicitud ID %lld no encontrada", RequestId);
        return STATUS_SUCCESS; // No es un error crítico
    }

    // Determinar el estado de bloqueo
    blockState = AllowInstallation ? BlockStateAllowed : BlockStateBlocked;

    // Completar la operación según la respuesta
    status = InstallGuardCompleteOperation(data, blockState);
    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_NOTIFICATION, "InstallGuard: Error al completar operación: 0x%08X", status);
    }

    // Liberar referencia a datos
    FltDereferenceOperationContext(data);

    return status;
}

/*++

Rutina:

    InstallGuardGetPendingRequestState

Descripción:

    Obtiene el estado actual de una solicitud pendiente.

Argumentos:

    RequestId - ID de la solicitud

Valor devuelto:

    Estado de la solicitud (enum INSTALLGUARD_BLOCK_STATE)

--*/
INSTALLGUARD_BLOCK_STATE
InstallGuardGetPendingRequestState(
    _In_ LONGLONG RequestId
)
{
    PLIST_ENTRY entry;
    PINSTALLGUARD_PENDING_CONTEXT pendingContext = NULL;
    INSTALLGUARD_BLOCK_STATE state = BlockStateUnknown;
    LARGE_INTEGER currentTime;
    LARGE_INTEGER timeout;

    // Obtener tiempo actual
    KeQuerySystemTime(&currentTime);
    timeout.QuadPart = INSTALLGUARD_NOTIFICATION_TIMEOUT;

    // Adquirir el bloqueo de recursos
    ExAcquireResourceSharedLite(&gPendingRequestsLock, TRUE);

    // Buscar la solicitud en la lista
    for (entry = gPendingRequestsList.Flink; entry != &gPendingRequestsList; entry = entry->Flink) {
        pendingContext = CONTAINING_RECORD(entry, INSTALLGUARD_PENDING_CONTEXT, ListEntry);
        if (pendingContext->RequestId == RequestId) {
            // Verificar si ha expirado el tiempo de espera
            if (currentTime.QuadPart - pendingContext->CreationTime.QuadPart > timeout.QuadPart) {
                state = BlockStateTimedOut;
            }
            else {
                state = pendingContext->IsInstallationAllowed ? BlockStateAllowed : BlockStatePending;
            }
            break;
        }
    }

    // Liberar el bloqueo
    ExReleaseResourceLite(&gPendingRequestsLock);

    return state;
}

/*++

Rutina:

    InstallGuardCompleteOperation

Descripción:

    Completa una operación pendiente según el estado de bloqueo.

Argumentos:

    Data - Puntero a la estructura de datos de callback
    BlockState - Estado de bloqueo para la operación

Valor devuelto:

    STATUS_SUCCESS si la operación fue completada correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardCompleteOperation(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ INSTALLGUARD_BLOCK_STATE BlockState
)
{
    NTSTATUS status = STATUS_SUCCESS;

    switch (BlockState) {
    case BlockStateAllowed:
        // Permitir la operación
        LOG_INFO(TRACE_NOTIFICATION, "InstallGuard: Permitiendo operación");
        Data->IoStatus.Status = STATUS_SUCCESS;
        Data->IoStatus.Information = 0;
        break;

    case BlockStateBlocked:
        // Denegar la operación
        LOG_INFO(TRACE_NOTIFICATION, "InstallGuard: Bloqueando operación");
        Data->IoStatus.Status = STATUS_ACCESS_DENIED;
        Data->IoStatus.Information = 0;
        break;

    case BlockStateTimedOut:
        // Tiempo de espera agotado, denegar por defecto
        LOG_WARNING(TRACE_NOTIFICATION, "InstallGuard: Tiempo de espera agotado, bloqueando operación");
        Data->IoStatus.Status = STATUS_TIMEOUT;
        Data->IoStatus.Information = 0;
        break;

    default:
        // Estado desconocido, denegar por seguridad
        LOG_ERROR(TRACE_NOTIFICATION, "InstallGuard: Estado de bloqueo desconocido: %d", BlockState);
        Data->IoStatus.Status = STATUS_ACCESS_DENIED;
        Data->IoStatus.Information = 0;
        break;
    }

    // Completar la operación
    FltCompletePendedPreOperation(
        Data,
        FLT_PREOP_COMPLETE,
        NULL
    );

    return status;
}

/*++

Rutina:

    InstallGuardNotifyCleanupFiles

Descripción:

    Notifica que los archivos de una instalación denegada deben ser limpiados.

Argumentos:

    FilePath - Puntero a la ruta del archivo a limpiar

Valor devuelto:

    Ninguno

--*/
VOID
InstallGuardNotifyCleanupFiles(
    _In_ PCUNICODE_STRING FilePath
)
{
    NTSTATUS status;
    INSTALLGUARD_MESSAGE message;

    // Si no hay cliente conectado, no podemos enviar notificación
    if (gClientPort == NULL) {
        LOG_WARNING(TRACE_NOTIFICATION, "InstallGuard: No hay cliente conectado para notificar limpieza");
        return;
    }

    LOG_INFO(TRACE_NOTIFICATION, "InstallGuard: Notificando limpieza de archivos: %wZ", FilePath);

    // Inicializar estructura de mensaje
    RtlZeroMemory(&message, sizeof(message));
    message.CommandCode = INSTALLGUARD_CMD_CLEANUP_REQUEST;
    message.Size = sizeof(message);

    // Copiar ruta del archivo
    if (FilePath->Length < sizeof(message.FilePath)) {
        RtlCopyMemory(message.FilePath, FilePath->Buffer, FilePath->Length);
        message.FilePath[FilePath->Length / sizeof(WCHAR)] = L'\0';
    }
    else {
        // Truncar nombre si es demasiado largo
        RtlCopyMemory(message.FilePath, FilePath->Buffer, sizeof(message.FilePath) - sizeof(WCHAR));
        message.FilePath[(sizeof(message.FilePath) / sizeof(WCHAR)) - 1] = L'\0';
    }

    // Enviar mensaje al servicio
    status = InstallGuardSendMessageToService(&message);
    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_NOTIFICATION, "InstallGuard: Error al enviar notificación de limpieza: 0x%08X", status);
        return;
    }

    LOG_INFO(TRACE_NOTIFICATION, "InstallGuard: Notificación de limpieza enviada correctamente");
} 