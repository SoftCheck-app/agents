/*++

Módulo:

    communication.h

Descripción:

    Declaraciones y definiciones para la comunicación entre el controlador
    minifiltro y el servicio de Windows en modo usuario.

--*/

#ifndef _INSTALLGUARD_COMMUNICATION_H_
#define _INSTALLGUARD_COMMUNICATION_H_

#include "driver.h"

//
// Prototipos de funciones
//

NTSTATUS
InstallGuardInitializePortCommunication(
    _In_ PFLT_FILTER Filter
);

VOID
InstallGuardClosePortCommunication(
    VOID
);

NTSTATUS
InstallGuardConnectNotifyCallback(
    _In_ PFLT_PORT ClientPort,
    _In_opt_ PVOID ServerPortCookie,
    _In_reads_bytes_opt_(SizeOfContext) PVOID ConnectionContext,
    _In_ ULONG SizeOfContext,
    _Outptr_result_maybenull_ PVOID* ConnectionPortCookie
);

VOID
InstallGuardDisconnectNotifyCallback(
    _In_opt_ PVOID ConnectionCookie
);

NTSTATUS
InstallGuardMessageNotifyCallback(
    _In_opt_ PVOID ConnectionCookie,
    _In_reads_bytes_opt_(InputBufferSize) PVOID InputBuffer,
    _In_ ULONG InputBufferSize,
    _Out_writes_bytes_to_opt_(OutputBufferSize, *ReturnOutputBufferLength) PVOID OutputBuffer,
    _In_ ULONG OutputBufferSize,
    _Out_ PULONG ReturnOutputBufferLength
);

NTSTATUS
InstallGuardSendMessageToService(
    _In_ PINSTALLGUARD_MESSAGE Message
);

NTSTATUS
InstallGuardProcessResponse(
    _In_ PINSTALLGUARD_RESPONSE Response
);

// Funciones auxiliares para obtener información del contexto de ejecución
NTSTATUS
InstallGuardGetProcessName(
    _In_ HANDLE ProcessId,
    _Out_ PUNICODE_STRING ProcessName
);

NTSTATUS
InstallGuardGetCurrentUsername(
    _Out_ PUNICODE_STRING Username
);

NTSTATUS
InstallGuardGetFileSize(
    _In_ PFLT_INSTANCE Instance,
    _In_ PFILE_OBJECT FileObject,
    _Out_ PLONGLONG FileSize
);

#endif // _INSTALLGUARD_COMMUNICATION_H_ 