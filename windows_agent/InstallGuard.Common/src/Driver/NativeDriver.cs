using System.Runtime.InteropServices;

namespace InstallGuard.Common.Driver
{
    /// <summary>
    /// Constantes y definiciones para la comunicación con el controlador
    /// </summary>
    public static class NativeDriverConstants
    {
        // Nombre del puerto de comunicación
        public const string PortName = "\\InstallGuardPort";

        // Códigos de comando
        public const uint INSTALLGUARD_CMD_INSTALL_REQUEST = 0x1001;
        public const uint INSTALLGUARD_CMD_INSTALL_RESPONSE = 0x1002;
        public const uint INSTALLGUARD_CMD_CLEANUP_REQUEST = 0x1003;

        // Tamaños máximos
        public const int MAX_PATH = 1024;
        public const int MAX_PROCESS_NAME = 256;
        public const int MAX_USERNAME = 256;
        public const int MAX_REASON = 512;
    }

    /// <summary>
    /// Estructura para mensajes de instalación recibidos del controlador
    /// </summary>
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct InstallGuardMessage
    {
        public uint CommandCode;
        public uint Size;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = NativeDriverConstants.MAX_PATH)]
        public string FilePath;
        public long FileSize;
        public uint ProcessId;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = NativeDriverConstants.MAX_PROCESS_NAME)]
        public string ProcessName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = NativeDriverConstants.MAX_USERNAME)]
        public string Username;
        public long Timestamp;
    }

    /// <summary>
    /// Estructura para respuestas a mensajes de instalación enviadas al controlador
    /// </summary>
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct InstallGuardResponse
    {
        public uint CommandCode;
        public uint RequestId;
        [MarshalAs(UnmanagedType.I1)]
        public bool AllowInstallation;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = NativeDriverConstants.MAX_REASON)]
        public string Reason;

        public static InstallGuardResponse Create(uint requestId, bool allowInstallation, string reason)
        {
            return new InstallGuardResponse
            {
                CommandCode = NativeDriverConstants.INSTALLGUARD_CMD_INSTALL_RESPONSE,
                RequestId = requestId,
                AllowInstallation = allowInstallation,
                Reason = reason ?? string.Empty
            };
        }
    }
} 