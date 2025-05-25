/*++

Módulo:

    filter.h

Descripción:

    Declaraciones y definiciones para las operaciones de filtrado 
    de archivos del controlador minifiltro InstallGuard.

--*/

#ifndef _INSTALLGUARD_FILTER_H_
#define _INSTALLGUARD_FILTER_H_

#include "driver.h"

//
// Prototipos de funciones
//

// Rutinas de operación preasignadas
FLT_PREOP_CALLBACK_STATUS
InstallGuardPreCreate(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Flt_CompletionContext_Outptr_ PVOID* CompletionContext
);

FLT_PREOP_CALLBACK_STATUS
InstallGuardPreWrite(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Flt_CompletionContext_Outptr_ PVOID* CompletionContext
);

FLT_PREOP_CALLBACK_STATUS
InstallGuardPreSetInformation(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Flt_CompletionContext_Outptr_ PVOID* CompletionContext
);

// Rutinas de operación postasignadas
FLT_POSTOP_CALLBACK_STATUS
InstallGuardPostCreate(
    _Inout_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_opt_ PVOID CompletionContext,
    _In_ FLT_POST_OPERATION_FLAGS Flags
);

// Funciones de utilidad para filtrado
BOOLEAN
InstallGuardIsInstallerFile(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects
);

NTSTATUS
InstallGuardGetFileNameInformation(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _Out_ PFLT_FILE_NAME_INFORMATION* NameInfo
);

BOOLEAN
InstallGuardCheckFileExtension(
    _In_ PCUNICODE_STRING Extension
);

NTSTATUS
InstallGuardSendInstallationMessage(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ PCFLT_RELATED_OBJECTS FltObjects,
    _In_ PCUNICODE_STRING FilePath
);

NTSTATUS
InstallGuardAddPendingRequest(
    _In_ PFLT_CALLBACK_DATA Data,
    _In_ LONGLONG RequestId
);

NTSTATUS
InstallGuardFindAndRemovePendingRequest(
    _In_ LONGLONG RequestId,
    _Out_ PFLT_CALLBACK_DATA* Data,
    _Out_ PBOOLEAN AllowInstallation
);

void
InstallGuardCleanupPendingRequests(
    _In_ BOOLEAN ForceCleanAll
);

#endif // _INSTALLGUARD_FILTER_H_ 