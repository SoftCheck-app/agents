/*++

Módulo:

    notification.h

Descripción:

    Declaraciones y definiciones para las notificaciones generadas por
    el controlador minifiltro InstallGuard.

--*/

#ifndef _INSTALLGUARD_NOTIFICATION_H_
#define _INSTALLGUARD_NOTIFICATION_H_

#include "driver.h"

//
// Definiciones y constantes
//

#define INSTALLGUARD_NOTIFICATION_TIMEOUT    (60 * 10 * 1000 * 1000) // 60 segundos en 100ns unidades

// Estados de bloqueo para las operaciones pendientes
typedef enum _INSTALLGUARD_BLOCK_STATE {
    BlockStateUnknown = 0,        // Estado no determinado
    BlockStatePending,            // Operación pendiente de evaluación
    BlockStateAllowed,            // Operación permitida
    BlockStateBlocked,            // Operación bloqueada
    BlockStateTimedOut            // Operación con tiempo de espera agotado
} INSTALLGUARD_BLOCK_STATE, *PINSTALLGUARD_BLOCK_STATE;

//
// Prototipos de funciones
//

NTSTATUS
InstallGuardNotifyInstallationAttempt(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ PCUNICODE_STRING FilePath
);

NTSTATUS
InstallGuardProcessInstallationResponse(
    _In_ LONGLONG RequestId,
    _In_ BOOLEAN AllowInstallation,
    _In_opt_ PCWSTR Reason
);

INSTALLGUARD_BLOCK_STATE
InstallGuardGetPendingRequestState(
    _In_ LONGLONG RequestId
);

NTSTATUS
InstallGuardCompleteOperation(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ INSTALLGUARD_BLOCK_STATE BlockState
);

VOID
InstallGuardNotifyCleanupFiles(
    _In_ PCUNICODE_STRING FilePath
);

#endif // _INSTALLGUARD_NOTIFICATION_H_ 