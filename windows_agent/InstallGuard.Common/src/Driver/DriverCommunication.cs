using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.ComponentModel;

namespace InstallGuard.Common.Driver
{
    /// <summary>
    /// Clase para la comunicación con el controlador minifiltro
    /// </summary>
    public class DriverCommunication : IDisposable
    {
        // Constantes para la comunicación con el sistema operativo
        private const uint FILE_DEVICE_UNKNOWN = 0x00000022;
        private const uint FILE_ANY_ACCESS = 0;
        private const uint METHOD_BUFFERED = 0;
        private const uint FILE_SHARE_READ = 1;
        private const uint FILE_SHARE_WRITE = 2;
        private const uint OPEN_EXISTING = 3;
        private const uint IOCTL_FLTMGR_BASE = FILE_DEVICE_UNKNOWN;
        private const uint FLT_MGR_CONNECT = ((IOCTL_FLTMGR_BASE) << 16) | ((FILE_ANY_ACCESS) << 14) | ((0x103) << 2) | (METHOD_BUFFERED);

        // Importaciones de funciones nativas de Windows
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern SafeFileHandle CreateFile(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(
            SafeFileHandle hDevice,
            uint dwIoControlCode,
            IntPtr lpInBuffer,
            uint nInBufferSize,
            IntPtr lpOutBuffer,
            uint nOutBufferSize,
            out uint lpBytesReturned,
            IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool ReadFile(
            SafeFileHandle hFile,
            IntPtr lpBuffer,
            uint nNumberOfBytesToRead,
            out uint lpNumberOfBytesRead,
            IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool WriteFile(
            SafeFileHandle hFile,
            IntPtr lpBuffer,
            uint nNumberOfBytesToWrite,
            out uint lpNumberOfBytesWritten,
            IntPtr lpOverlapped);

        private SafeFileHandle _portHandle;
        private bool _disposed = false;
        private readonly ILogger<DriverCommunication> _logger;

        /// <summary>
        /// Representa si el controlador está conectado
        /// </summary>
        public bool IsConnected => _portHandle != null && !_portHandle.IsInvalid;

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="logger">Logger para registrar eventos</param>
        public DriverCommunication(ILogger<DriverCommunication> logger)
        {
            _logger = logger;
        }

        /// <summary>
        /// Conecta con el controlador minifiltro
        /// </summary>
        /// <returns>True si se conecta correctamente, false en caso contrario</returns>
        public bool Connect()
        {
            try
            {
                if (IsConnected)
                {
                    _logger.LogWarning("Intento de conectar al controlador cuando ya hay una conexión activa");
                    return true;
                }

                _logger.LogInformation("Conectando con el controlador minifiltro...");

                // Abrir el puerto de comunicación
                _portHandle = CreateFile(
                    NativeDriverConstants.PortName,
                    0xC0000000, // GENERIC_READ | GENERIC_WRITE
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    IntPtr.Zero,
                    OPEN_EXISTING,
                    0,
                    IntPtr.Zero);

                if (_portHandle.IsInvalid)
                {
                    int error = Marshal.GetLastWin32Error();
                    _logger.LogError("Error al conectar con el controlador: {Error}", new Win32Exception(error).Message);
                    return false;
                }

                // Enviar mensaje de conexión
                uint bytesReturned = 0;
                bool result = DeviceIoControl(
                    _portHandle,
                    FLT_MGR_CONNECT,
                    IntPtr.Zero,
                    0,
                    IntPtr.Zero,
                    0,
                    out bytesReturned,
                    IntPtr.Zero);

                if (!result)
                {
                    int error = Marshal.GetLastWin32Error();
                    _logger.LogError("Error al inicializar la conexión con el controlador: {Error}", new Win32Exception(error).Message);
                    _portHandle.Close();
                    return false;
                }

                _logger.LogInformation("Conexión con el controlador establecida correctamente");
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Excepción al conectar con el controlador minifiltro");
                if (_portHandle != null && !_portHandle.IsInvalid)
                {
                    _portHandle.Close();
                }
                return false;
            }
        }

        /// <summary>
        /// Lee un mensaje del controlador minifiltro
        /// </summary>
        /// <returns>Mensaje recibido o null si hay un error</returns>
        public InstallGuardMessage? ReadMessage()
        {
            if (!IsConnected)
            {
                _logger.LogWarning("Intento de leer un mensaje cuando no hay conexión con el controlador");
                return null;
            }

            int messageSize = Marshal.SizeOf<InstallGuardMessage>();
            IntPtr buffer = Marshal.AllocHGlobal(messageSize);

            try
            {
                uint bytesRead = 0;
                bool result = ReadFile(
                    _portHandle,
                    buffer,
                    (uint)messageSize,
                    out bytesRead,
                    IntPtr.Zero);

                if (!result || bytesRead == 0)
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error != 0) // 0 puede significar que no hay mensajes disponibles
                    {
                        _logger.LogError("Error al leer mensaje del controlador: {Error}", new Win32Exception(error).Message);
                    }
                    return null;
                }

                // Convertir buffer a estructura
                InstallGuardMessage message = Marshal.PtrToStructure<InstallGuardMessage>(buffer);
                return message;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Excepción al leer mensaje del controlador");
                return null;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        /// <summary>
        /// Envía una respuesta al controlador minifiltro
        /// </summary>
        /// <param name="response">Respuesta a enviar</param>
        /// <returns>True si se envía correctamente, false en caso contrario</returns>
        public bool SendResponse(InstallGuardResponse response)
        {
            if (!IsConnected)
            {
                _logger.LogWarning("Intento de enviar respuesta cuando no hay conexión con el controlador");
                return false;
            }

            int responseSize = Marshal.SizeOf<InstallGuardResponse>();
            IntPtr buffer = Marshal.AllocHGlobal(responseSize);

            try
            {
                // Convertir estructura a buffer
                Marshal.StructureToPtr(response, buffer, false);

                uint bytesWritten = 0;
                bool result = WriteFile(
                    _portHandle,
                    buffer,
                    (uint)responseSize,
                    out bytesWritten,
                    IntPtr.Zero);

                if (!result || bytesWritten != responseSize)
                {
                    int error = Marshal.GetLastWin32Error();
                    _logger.LogError("Error al enviar respuesta al controlador: {Error}", new Win32Exception(error).Message);
                    return false;
                }

                _logger.LogInformation("Respuesta enviada correctamente al controlador. RequestId: {RequestId}, Allow: {Allow}", 
                    response.RequestId, response.AllowInstallation);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Excepción al enviar respuesta al controlador");
                return false;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        /// <summary>
        /// Desconecta del controlador minifiltro
        /// </summary>
        public void Disconnect()
        {
            if (IsConnected)
            {
                _logger.LogInformation("Desconectando del controlador minifiltro");
                _portHandle.Close();
                _portHandle = null;
            }
        }

        /// <summary>
        /// Libera los recursos utilizados
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Libera los recursos utilizados
        /// </summary>
        /// <param name="disposing">True si se llama desde Dispose, false si se llama desde el finalizador</param>
        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    Disconnect();
                }

                _disposed = true;
            }
        }

        /// <summary>
        /// Destructor
        /// </summary>
        ~DriverCommunication()
        {
            Dispose(false);
        }
    }
} 