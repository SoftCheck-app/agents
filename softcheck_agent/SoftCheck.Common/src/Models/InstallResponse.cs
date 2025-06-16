namespace SoftCheck.Common.Models
{
    /// <summary>
    /// Modelo para la respuesta a una solicitud de instalación
    /// </summary>
    public class InstallResponse
    {
        /// <summary>
        /// Identificador único de la solicitud de instalación
        /// </summary>
        public long RequestId { get; set; }

        /// <summary>
        /// Indica si se permite la instalación
        /// </summary>
        public bool AllowInstallation { get; set; }

        /// <summary>
        /// Razón por la que se permite o se deniega la instalación
        /// </summary>
        public string Reason { get; set; } = string.Empty;

        /// <summary>
        /// Fecha y hora en que se generó la respuesta
        /// </summary>
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
} 
