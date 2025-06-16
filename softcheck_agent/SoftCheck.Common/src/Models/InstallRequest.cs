namespace SoftCheck.Common.Models
{
    /// <summary>
    /// Modelo para una solicitud de instalación
    /// </summary>
    public class InstallRequest
    {
        /// <summary>
        /// ID de la solicitud
        /// </summary>
        public long RequestId { get; set; }

        /// <summary>
        /// Ruta del archivo a instalar
        /// </summary>
        public string FilePath { get; set; } = string.Empty;

        /// <summary>
        /// Tamaño del archivo en bytes
        /// </summary>
        public long FileSize { get; set; }

        /// <summary>
        /// Hash del archivo (SHA256)
        /// </summary>
        public string? FileHash { get; set; }

        /// <summary>
        /// ID del proceso que intenta la instalación
        /// </summary>
        public int ProcessId { get; set; }

        /// <summary>
        /// Nombre del proceso que intenta la instalación
        /// </summary>
        public string ProcessName { get; set; } = string.Empty;

        /// <summary>
        /// Nombre del usuario que intenta la instalación
        /// </summary>
        public string Username { get; set; } = string.Empty;

        /// <summary>
        /// Marca de tiempo de la solicitud
        /// </summary>
        public DateTime Timestamp { get; set; }
    }
} 
