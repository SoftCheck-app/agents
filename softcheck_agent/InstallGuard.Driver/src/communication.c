/*++

Módulo:

    communication.c

Descripción:

    Implementación de las funciones de comunicación entre el controlador
    minifiltro y el servicio de Windows en modo usuario.

--*/

#include "communication.h"
#include "notification.h"

/*++

Rutina:

    InstallGuardInitializePortCommunication

Descripción:

    Inicializa la comunicación mediante puerto con el servicio en modo usuario.

Argumentos:

    Filter - Puntero al objeto de filtro

Valor devuelto:

    STATUS_SUCCESS si la inicialización fue exitosa, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardInitializePortCommunication(
    _In_ PFLT_FILTER Filter
)
{
    NTSTATUS status;
    PSECURITY_DESCRIPTOR securityDescriptor = NULL;
    OBJECT_ATTRIBUTES objectAttributes;
    UNICODE_STRING portName;

    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Iniciando comunicación por puerto");

    // Crear un descriptor de seguridad que permita a cualquier proceso conectarse
    status = FltBuildDefaultSecurityDescriptor(&securityDescriptor, FLT_PORT_ALL_ACCESS);
    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_COMMUNICATION, "InstallGuard: Error al crear descriptor de seguridad: 0x%08X", status);
        return status;
    }

    // Inicializar el nombre del puerto de comunicación
    RtlInitUnicodeString(&portName, INSTALLGUARD_PORT_NAME);

    // Inicializar los atributos del objeto para el puerto
    InitializeObjectAttributes(
        &objectAttributes,
        &portName,
        OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE,
        NULL,
        securityDescriptor
    );

    // Crear el puerto de comunicación
    status = FltCreateCommunicationPort(
        Filter,
        &gServerPort,
        &objectAttributes,
        NULL,                                  // ServerPortCookie
        InstallGuardConnectNotifyCallback,     // Callback de conexión
        InstallGuardDisconnectNotifyCallback,  // Callback de desconexión
        InstallGuardMessageNotifyCallback,     // Callback de mensaje
        INSTALLGUARD_MAX_CONNECTIONS           // Máximo de conexiones
    );

    // Liberar descriptor de seguridad (ya no lo necesitamos)
    FltFreeSecurityDescriptor(securityDescriptor);

    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_COMMUNICATION, "InstallGuard: Error al crear puerto de comunicación: 0x%08X", status);
        return status;
    }

    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Puerto de comunicación creado correctamente");
    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardClosePortCommunication

Descripción:

    Cierra el puerto de comunicación con el servicio en modo usuario.

Argumentos:

    Ninguno

Valor devuelto:

    Ninguno

--*/
VOID
InstallGuardClosePortCommunication(
    VOID
)
{
    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Cerrando puerto de comunicación");

    // Cerrar el puerto del cliente si está abierto
    if (gClientPort != NULL) {
        FltCloseClientPort(gFilterHandle, &gClientPort);
        gClientPort = NULL;
    }

    // Cerrar el puerto del servidor si está abierto
    if (gServerPort != NULL) {
        FltCloseCommunicationPort(gServerPort);
        gServerPort = NULL;
    }

    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Puerto de comunicación cerrado");
}

/*++

Rutina:

    InstallGuardConnectNotifyCallback

Descripción:

    Callback que maneja la conexión de un cliente al puerto.

Argumentos:

    ClientPort - Puerto del cliente que se está conectando
    ServerPortCookie - Cookie del puerto del servidor (no utilizado)
    ConnectionContext - Contexto de conexión proporcionado por el cliente
    SizeOfContext - Tamaño del contexto de conexión
    ConnectionPortCookie - Cookie del puerto de conexión (devuelto al cliente)

Valor devuelto:

    STATUS_SUCCESS si la conexión fue aceptada, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardConnectNotifyCallback(
    _In_ PFLT_PORT ClientPort,
    _In_opt_ PVOID ServerPortCookie,
    _In_reads_bytes_opt_(SizeOfContext) PVOID ConnectionContext,
    _In_ ULONG SizeOfContext,
    _Outptr_result_maybenull_ PVOID* ConnectionPortCookie
)
{
    UNREFERENCED_PARAMETER(ServerPortCookie);
    UNREFERENCED_PARAMETER(ConnectionContext);
    UNREFERENCED_PARAMETER(SizeOfContext);

    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Cliente conectado al puerto");

    // Si ya tenemos un cliente conectado, rechazar la conexión
    if (gClientPort != NULL) {
        LOG_WARNING(TRACE_COMMUNICATION, "InstallGuard: Ya hay un cliente conectado. Rechazando nueva conexión.");
        return STATUS_CONNECTION_REFUSED;
    }

    // Guardar el puerto del cliente
    gClientPort = ClientPort;
    *ConnectionPortCookie = NULL;

    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Conexión aceptada");
    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardDisconnectNotifyCallback

Descripción:

    Callback que maneja la desconexión de un cliente del puerto.

Argumentos:

    ConnectionCookie - Cookie de conexión (no utilizado)

Valor devuelto:

    Ninguno

--*/
VOID
InstallGuardDisconnectNotifyCallback(
    _In_opt_ PVOID ConnectionCookie
)
{
    UNREFERENCED_PARAMETER(ConnectionCookie);

    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Cliente desconectado del puerto");

    // Limpiar el puerto del cliente
    if (gClientPort != NULL) {
        FltCloseClientPort(gFilterHandle, &gClientPort);
        gClientPort = NULL;
    }

    // Limpiar las solicitudes pendientes (ya que no podemos procesarlas sin cliente)
    InstallGuardCleanupPendingRequests(TRUE);
}

/*++

Rutina:

    InstallGuardMessageNotifyCallback

Descripción:

    Callback que maneja los mensajes recibidos del cliente.

Argumentos:

    ConnectionCookie - Cookie de conexión (no utilizado)
    InputBuffer - Buffer de entrada que contiene el mensaje del cliente
    InputBufferSize - Tamaño del buffer de entrada
    OutputBuffer - Buffer de salida donde escribir la respuesta
    OutputBufferSize - Tamaño del buffer de salida
    ReturnOutputBufferLength - Tamaño de los datos escritos en el buffer de salida

Valor devuelto:

    STATUS_SUCCESS si el mensaje fue procesado correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardMessageNotifyCallback(
    _In_opt_ PVOID ConnectionCookie,
    _In_reads_bytes_opt_(InputBufferSize) PVOID InputBuffer,
    _In_ ULONG InputBufferSize,
    _Out_writes_bytes_to_opt_(OutputBufferSize, *ReturnOutputBufferLength) PVOID OutputBuffer,
    _In_ ULONG OutputBufferSize,
    _Out_ PULONG ReturnOutputBufferLength
)
{
    NTSTATUS status = STATUS_SUCCESS;
    PINSTALLGUARD_MESSAGE message = NULL;
    PINSTALLGUARD_RESPONSE response = NULL;

    UNREFERENCED_PARAMETER(ConnectionCookie);

    // Inicializar tamaño de salida a cero
    *ReturnOutputBufferLength = 0;

    // Validar buffer de entrada
    if (InputBuffer == NULL || InputBufferSize < sizeof(ULONG)) {
        return STATUS_INVALID_PARAMETER;
    }

    // Verificar comando
    ULONG commandCode = *(PULONG)InputBuffer;

    switch (commandCode) {
    case INSTALLGUARD_CMD_INSTALL_RESPONSE:
        // Procesar respuesta de instalación
        if (InputBufferSize < sizeof(INSTALLGUARD_RESPONSE)) {
            LOG_ERROR(TRACE_COMMUNICATION, "InstallGuard: Tamaño de respuesta de instalación inválido");
            return STATUS_INVALID_PARAMETER;
        }

        response = (PINSTALLGUARD_RESPONSE)InputBuffer;
        status = InstallGuardProcessResponse(response);
        break;

    default:
        // Comando desconocido
        LOG_WARNING(TRACE_COMMUNICATION, "InstallGuard: Comando desconocido recibido: 0x%08X", commandCode);
        status = STATUS_INVALID_PARAMETER;
        break;
    }

    return status;
}

/*++

Rutina:

    InstallGuardSendMessageToService

Descripción:

    Envía un mensaje al servicio en modo usuario.

Argumentos:

    Message - Puntero al mensaje a enviar

Valor devuelto:

    STATUS_SUCCESS si el mensaje fue enviado correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardSendMessageToService(
    _In_ PINSTALLGUARD_MESSAGE Message
)
{
    NTSTATUS status = STATUS_SUCCESS;
    
    // Verificar que tenemos un cliente conectado
    if (gClientPort == NULL) {
        LOG_ERROR(TRACE_COMMUNICATION, "InstallGuard: No hay cliente conectado para enviar mensaje");
        return STATUS_PORT_DISCONNECTED;
    }

    // Enviar mensaje al cliente
    status = FltSendMessage(
        gFilterHandle,
        &gClientPort,
        Message,
        Message->Size,
        NULL,
        NULL,
        NULL
    );

    if (!NT_SUCCESS(status)) {
        LOG_ERROR(TRACE_COMMUNICATION, "InstallGuard: Error al enviar mensaje: 0x%08X", status);
        return status;
    }

    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Mensaje enviado correctamente, código: 0x%08X", Message->CommandCode);
    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardProcessResponse

Descripción:

    Procesa una respuesta recibida del servicio.

Argumentos:

    Response - Puntero a la estructura de respuesta

Valor devuelto:

    STATUS_SUCCESS si la respuesta fue procesada correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardProcessResponse(
    _In_ PINSTALLGUARD_RESPONSE Response
)
{
    LOG_INFO(TRACE_COMMUNICATION, "InstallGuard: Procesando respuesta para solicitud ID %d", Response->RequestId);

    // Procesar la respuesta de instalación
    return InstallGuardProcessInstallationResponse(
        Response->RequestId,
        Response->AllowInstallation,
        Response->Reason
    );
}

/*++

Rutina:

    InstallGuardGetProcessName

Descripción:

    Obtiene el nombre del proceso a partir de su ID.

Argumentos:

    ProcessId - ID del proceso
    ProcessName - Puntero a la estructura UNICODE_STRING que recibirá el nombre

Valor devuelto:

    STATUS_SUCCESS si el nombre fue obtenido correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardGetProcessName(
    _In_ HANDLE ProcessId,
    _Out_ PUNICODE_STRING ProcessName
)
{
    NTSTATUS status;
    PEPROCESS process = NULL;
    PUNICODE_STRING imageName = NULL;
    WCHAR unknownProcess[] = L"<Desconocido>";

    RtlInitUnicodeString(ProcessName, unknownProcess);

    // Obtener el proceso a partir de su ID
    status = PsLookupProcessByProcessId(ProcessId, &process);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    // Obtener el nombre de la imagen del proceso
    status = SeLocateProcessImageName(process, &imageName);
    if (NT_SUCCESS(status) && imageName != NULL) {
        // Extraer solo el nombre del archivo, no la ruta completa
        USHORT lastSlash = 0;
        
        for (USHORT i = 0; i < imageName->Length / sizeof(WCHAR); i++) {
            if (imageName->Buffer[i] == L'\\') {
                lastSlash = i + 1;
            }
        }

        if (lastSlash < imageName->Length / sizeof(WCHAR)) {
            RtlInitUnicodeString(
                ProcessName,
                &imageName->Buffer[lastSlash]
            );
        }
        else {
            RtlCopyUnicodeString(ProcessName, imageName);
        }

        ExFreePool(imageName);
    }

    // Liberar la referencia al proceso
    ObDereferenceObject(process);

    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardGetCurrentUsername

Descripción:

    Obtiene el nombre del usuario actual.

Argumentos:

    Username - Puntero a la estructura UNICODE_STRING que recibirá el nombre

Valor devuelto:

    STATUS_SUCCESS si el nombre fue obtenido correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardGetCurrentUsername(
    _Out_ PUNICODE_STRING Username
)
{
    WCHAR unknownUser[] = L"<Desconocido>";
    
    // En el contexto del kernel, no podemos obtener fácilmente el nombre de usuario
    // Esta información se obtendrá en el servicio en modo usuario
    RtlInitUnicodeString(Username, unknownUser);
    
    return STATUS_SUCCESS;
}

/*++

Rutina:

    InstallGuardGetFileSize

Descripción:

    Obtiene el tamaño de un archivo.

Argumentos:

    Instance - Puntero a la instancia del filtro
    FileObject - Puntero al objeto de archivo
    FileSize - Puntero a la variable que recibirá el tamaño

Valor devuelto:

    STATUS_SUCCESS si el tamaño fue obtenido correctamente, o un código de error NTSTATUS.

--*/
NTSTATUS
InstallGuardGetFileSize(
    _In_ PFLT_INSTANCE Instance,
    _In_ PFILE_OBJECT FileObject,
    _Out_ PLONGLONG FileSize
)
{
    NTSTATUS status;
    FILE_STANDARD_INFORMATION fileInfo;

    // Inicializar tamaño a cero
    *FileSize = 0;

    // Obtener información estándar del archivo
    status = FltQueryInformationFile(
        Instance,
        FileObject,
        &fileInfo,
        sizeof(FILE_STANDARD_INFORMATION),
        FileStandardInformation,
        NULL
    );

    if (NT_SUCCESS(status)) {
        *FileSize = fileInfo.EndOfFile.QuadPart;
    }
    
    return status;
} 