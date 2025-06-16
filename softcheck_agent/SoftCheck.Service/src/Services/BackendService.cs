using System.Net.Http.Json;

namespace SoftCheck.Service.Services
{
    /// <summary>
    /// Implementación del servicio de comunicación con el backend
    /// </summary>
    public class BackendService : IBackendService
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<BackendService> _logger;
        private readonly IConfiguration _configuration;

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="httpClient">Cliente HTTP</param>
        /// <param name="logger">Logger para registrar eventos</param>
        /// <param name="configuration">Configuración de la aplicación</param>
        public BackendService(
            HttpClient httpClient,
            ILogger<BackendService> logger,
            IConfiguration configuration)
        {
            _httpClient = httpClient;
            _logger = logger;
            _configuration = configuration;

            // Configurar el cliente HTTP
            var backendUrl = _configuration["Backend:BaseUrl"] ?? "http://localhost:5000";
            _httpClient.BaseAddress = new Uri(backendUrl);
        }

        /// <summary>
        /// Verifica una solicitud de instalación con el backend
        /// </summary>
        /// <param name="request">Solicitud de verificación</param>
        /// <returns>Respuesta de verificación</returns>
        public async Task<InstallVerificationResponse> VerifyInstallationAsync(InstallVerificationRequest request)
        {
            try
            {
                _logger.LogInformation("Enviando solicitud de verificación al backend para: {FilePath}", request.FilePath);

                var response = await _httpClient.PostAsJsonAsync("/api/verify", request);
                
                if (response.IsSuccessStatusCode)
                {
                    var verificationResponse = await response.Content.ReadFromJsonAsync<InstallVerificationResponse>();
                    
                    if (verificationResponse != null)
                    {
                        _logger.LogInformation("Respuesta recibida del backend: {IsApproved}, {Reason}",
                            verificationResponse.IsApproved, verificationResponse.Reason);
                        return verificationResponse;
                    }
                }

                _logger.LogError("Error al verificar la instalación. Código de estado: {StatusCode}", response.StatusCode);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al comunicarse con el backend");
            }

            // En caso de error, denegar por defecto por seguridad
            return new InstallVerificationResponse
            {
                IsApproved = false,
                Reason = "Error al verificar la instalación con el backend"
            };
        }
    }
} 
