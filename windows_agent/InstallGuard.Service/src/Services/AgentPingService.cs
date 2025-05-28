using System.Net.Http.Json;
using System.Management;

namespace InstallGuard.Service.Services
{
    /// <summary>
    /// Servicio para enviar pings periódicos al backend
    /// </summary>
    public class AgentPingService : BackgroundService
    {
        private readonly ILogger<AgentPingService> _logger;
        private readonly HttpClient _httpClient;
        private readonly IConfiguration _configuration;
        private readonly TimeSpan _pingInterval = TimeSpan.FromMinutes(1);
        private readonly string _apiKey;

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="logger">Logger para registrar eventos</param>
        /// <param name="httpClientFactory">Cliente HTTP</param>
        /// <param name="configuration">Configuración de la aplicación</param>
        public AgentPingService(
            ILogger<AgentPingService> logger,
            IHttpClientFactory httpClientFactory,
            IConfiguration configuration)
        {
            _logger = logger;
            _configuration = configuration;
            _httpClient = httpClientFactory.CreateClient();
            
            var backendUrl = configuration["Backend:BaseUrl"] ?? "http://localhost:4002";
            _httpClient.BaseAddress = new Uri(backendUrl);
            
            _apiKey = configuration["Backend:ApiKey"] ?? "83dc386a4a636411e068f86bbe5de3bd";
            
            // Configurar headers por defecto
            _httpClient.DefaultRequestHeaders.Add("x-api-key", _apiKey);
            _httpClient.DefaultRequestHeaders.Add("Accept", "application/json");
            _httpClient.DefaultRequestHeaders.Add("User-Agent", "SoftCheck-Agent/1.0");
        }

        /// <summary>
        /// Método principal del servicio en segundo plano
        /// </summary>
        /// <param name="stoppingToken">Token de cancelación</param>
        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Servicio de ping iniciado");

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await SendPingAsync();
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error al enviar ping al backend");
                }

                await Task.Delay(_pingInterval, stoppingToken);
            }

            _logger.LogInformation("Servicio de ping detenido");
        }

        /// <summary>
        /// Envía un ping al backend
        /// </summary>
        private async Task SendPingAsync()
        {
            try
            {
                var deviceId = GetDeviceId();
                var username = GetUsername();
                
                var pingData = new AgentPingRequest
                {
                    DeviceId = deviceId,
                    EmployeeEmail = $"{username}@example.com",
                    Status = "active"
                };

                _logger.LogDebug("Enviando ping al servidor...");
                _logger.LogDebug("Device ID: {DeviceId}", deviceId);

                var response = await _httpClient.PostAsJsonAsync("/api/agents/ping", pingData);
                
                if (response.IsSuccessStatusCode)
                {
                    var responseContent = await response.Content.ReadAsStringAsync();
                    _logger.LogInformation("Ping exitoso: Estado del agente actualizado en el servidor");
                    
                    // Verificar si se debe actualizar el agente
                    if (responseContent.Contains("\"shouldUpdate\":true"))
                    {
                        _logger.LogInformation("El servidor indica que se debe actualizar el agente");
                        // TODO: Implementar lógica de actualización
                    }
                }
                else
                {
                    _logger.LogWarning("Error en ping: No se pudo actualizar el estado del agente. Código: {StatusCode}", response.StatusCode);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al enviar ping al backend");
                throw;
            }
        }

        /// <summary>
        /// Obtiene el ID único del dispositivo
        /// </summary>
        private string GetDeviceId()
        {
            try
            {
                // Intentar obtener el número de serie del sistema
                using var searcher = new ManagementObjectSearcher("SELECT SerialNumber FROM Win32_BIOS");
                foreach (ManagementObject obj in searcher.Get())
                {
                    var serial = obj["SerialNumber"]?.ToString();
                    if (!string.IsNullOrEmpty(serial))
                    {
                        return $"SERIAL-{serial}";
                    }
                }

                // Si no se puede obtener el número de serie, usar el nombre de la máquina
                return $"MACHINE-{Environment.MachineName}";
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error al obtener device ID, usando nombre de máquina");
                return $"MACHINE-{Environment.MachineName}";
            }
        }

        /// <summary>
        /// Obtiene el nombre de usuario actual
        /// </summary>
        private string GetUsername()
        {
            return Environment.UserName;
        }
    }

    /// <summary>
    /// Modelo para una solicitud de ping
    /// </summary>
    public class AgentPingRequest
    {
        /// <summary>
        /// ID único del dispositivo
        /// </summary>
        public string DeviceId { get; set; } = string.Empty;

        /// <summary>
        /// Email del empleado
        /// </summary>
        public string EmployeeEmail { get; set; } = string.Empty;

        /// <summary>
        /// Estado del agente
        /// </summary>
        public string Status { get; set; } = string.Empty;
    }
} 