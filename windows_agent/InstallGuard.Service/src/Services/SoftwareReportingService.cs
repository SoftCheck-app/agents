using InstallGuard.Common.Models;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System.Text;
using System.Text.Json;
using System.Net.Http;
using System.Security.Cryptography;
using System.Management;

namespace InstallGuard.Service.Services
{
    public class SoftwareReportingService : ISoftwareReportingService
    {
        private readonly ILogger<SoftwareReportingService> _logger;
        private readonly IConfiguration _configuration;
        private readonly HttpClient _httpClient;
        private readonly string _apiKey;
        private readonly string _baseUrl;
        private readonly string _deviceId;
        private readonly string _teamName;

        public SoftwareReportingService(
            ILogger<SoftwareReportingService> logger,
            IConfiguration configuration,
            HttpClient httpClient)
        {
            _logger = logger;
            _configuration = configuration;
            _httpClient = httpClient;
            
            // Configurar desde appsettings.json
            _apiKey = _configuration["SoftCheck:ApiKey"] ?? "c07f7b249e2b4b970a04f97b169db6a5";
            _baseUrl = _configuration["SoftCheck:BaseUrl"] ?? "http://localhost:4002/api";
            _teamName = _configuration["SoftCheck:TeamName"] ?? "myteam";
            _deviceId = GetDeviceId();

            // Configurar HttpClient
            _httpClient.DefaultRequestHeaders.Add("X-API-KEY", _apiKey);
            _httpClient.DefaultRequestHeaders.Add("Accept", "application/json");
            _httpClient.DefaultRequestHeaders.Add("User-Agent", "InstallGuard-Agent/2.0");
            _httpClient.Timeout = TimeSpan.FromSeconds(30);
            
            _logger.LogInformation("SoftwareReportingService configurado para team: {TeamName}", _teamName);
        }

        public async Task<bool> ReportInstallationAsync(InstallationEvent installationEvent)
        {
            try
            {
                if (installationEvent?.Application == null)
                {
                    _logger.LogWarning("No se puede reportar instalación: datos de aplicación nulos");
                    return false;
                }

                var userId = GetCurrentUserId();
                return await ReportApplicationAsync(installationEvent.Application, _deviceId, userId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reportando instalación a la webapp");
                return false;
            }
        }

        public async Task<bool> ReportApplicationAsync(ApplicationInfo applicationInfo, string deviceId, string userId)
        {
            try
            {
                _logger.LogInformation($"Enviando datos de aplicación a webapp: {applicationInfo.Name} v{applicationInfo.Version}");

                // Crear el payload JSON siguiendo el formato esperado por validate_software.ts
                var payload = new
                {
                    device_id = deviceId,
                    user_id = userId,
                    software_name = applicationInfo.Name,
                    version = applicationInfo.Version,
                    vendor = !string.IsNullOrEmpty(applicationInfo.Publisher) ? applicationInfo.Publisher : "Unknown",
                    install_date = ParseInstallDate(applicationInfo.InstallDate),
                    install_path = applicationInfo.InstallLocation,
                    install_method = DetermineInstallMethod(applicationInfo),
                    last_executed = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                    is_running = IsApplicationRunning(applicationInfo.Name),
                    digital_signature = !string.IsNullOrEmpty(applicationInfo.DigitalSignature),
                    is_approved = false, // Por defecto no aprobado
                    detected_by = "windows_agent",
                    sha256 = !string.IsNullOrEmpty(applicationInfo.FileHash) ? applicationInfo.FileHash : CalculateApplicationHash(applicationInfo),
                    notes = BuildNotesFromApplicationInfo(applicationInfo)
                };

                var jsonContent = JsonSerializer.Serialize(payload, new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                    WriteIndented = false
                });

                _logger.LogDebug($"Payload JSON: {jsonContent}");

                var content = new StringContent(jsonContent, Encoding.UTF8, "application/json");
                var endpoint = $"{_baseUrl}/validate_software";

                var response = await _httpClient.PostAsync(endpoint, content);
                var responseContent = await response.Content.ReadAsStringAsync();

                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation($"Aplicación reportada exitosamente: {applicationInfo.Name}");
                    _logger.LogDebug($"Respuesta del servidor: {responseContent}");
                    
                    // Procesar respuesta para obtener información de aprobación
                    await ProcessServerResponse(responseContent, applicationInfo);
                    
                    return true;
                }
                else
                {
                    _logger.LogWarning($"Error al reportar aplicación. Status: {response.StatusCode}, Response: {responseContent}");
                    return false;
                }
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "Error de conectividad al reportar aplicación");
                return false;
            }
            catch (TaskCanceledException ex)
            {
                _logger.LogError(ex, "Timeout al reportar aplicación");
                return false;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error inesperado al reportar aplicación");
                return false;
            }
        }

        public async Task<bool> TestConnectivityAsync()
        {
            try
            {
                _logger.LogInformation("Probando conectividad con la webapp...");
                
                var endpoint = $"{_baseUrl}/health";
                var response = await _httpClient.GetAsync(endpoint);
                
                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation("Conectividad con webapp confirmada");
                    return true;
                }
                else
                {
                    _logger.LogWarning($"Problema de conectividad. Status: {response.StatusCode}");
                    return false;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error probando conectividad con webapp");
                return false;
            }
        }

        /// <summary>
        /// Envía múltiples aplicaciones en lotes para optimizar el rendimiento
        /// </summary>
        public async Task<(int successful, int failed)> ReportInventoryBatchAsync(List<ApplicationInfo> applications, int batchSize = 10)
        {
            int successCount = 0;
            int failCount = 0;
            var userId = GetCurrentUserId();

            _logger.LogInformation($"Enviando inventario de {applications.Count} aplicaciones en lotes de {batchSize}");

            // Procesar en lotes para no sobrecargar la webapp
            for (int i = 0; i < applications.Count; i += batchSize)
            {
                var batch = applications.Skip(i).Take(batchSize).ToList();
                _logger.LogDebug($"Procesando lote {(i / batchSize) + 1}: {batch.Count} aplicaciones");

                // Procesar cada aplicación del lote
                var batchTasks = batch.Select(async app =>
                {
                    try
                    {
                        var success = await ReportApplicationAsync(app, _deviceId, userId);
                        return success;
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, $"Error enviando aplicación en lote: {app.Name}");
                        return false;
                    }
                });

                // Esperar a que se complete el lote
                var results = await Task.WhenAll(batchTasks);
                
                // Contar resultados
                successCount += results.Count(r => r);
                failCount += results.Count(r => !r);

                // Pausa entre lotes para no sobrecargar el servidor
                if (i + batchSize < applications.Count)
                {
                    await Task.Delay(1000); // 1 segundo entre lotes
                }
            }

            _logger.LogInformation($"Inventario completado: {successCount} exitosas, {failCount} fallidas");
            return (successCount, failCount);
        }

        private string GetDeviceId()
        {
            try
            {
                // Intentar obtener el número de serie del sistema
                using var searcher = new ManagementObjectSearcher("SELECT SerialNumber FROM Win32_BaseBoard");
                foreach (ManagementObject obj in searcher.Get())
                {
                    var serialNumber = obj["SerialNumber"]?.ToString();
                    if (!string.IsNullOrEmpty(serialNumber) && serialNumber != "To be filled by O.E.M.")
                    {
                        return $"WIN-{serialNumber}";
                    }
                }

                // Fallback: usar nombre de máquina + hash del usuario
                var machineName = Environment.MachineName;
                var userName = Environment.UserName;
                var combined = $"{machineName}-{userName}";
                
                using var sha256 = SHA256.Create();
                var hash = sha256.ComputeHash(Encoding.UTF8.GetBytes(combined));
                var hashString = Convert.ToHexString(hash)[..8]; // Primeros 8 caracteres
                
                return $"WIN-{machineName}-{hashString}";
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error obteniendo device ID, usando fallback");
                return $"WIN-{Environment.MachineName}-{Environment.UserName}";
            }
        }

        private string GetCurrentUserId()
        {
            try
            {
                // Usar el nombre de usuario del sistema
                var userName = Environment.UserName;
                var domainName = Environment.UserDomainName;
                
                if (!string.IsNullOrEmpty(domainName) && domainName != Environment.MachineName)
                {
                    return $"{domainName}\\{userName}";
                }
                
                return userName;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error obteniendo user ID");
                return "Unknown";
            }
        }

        private string ParseInstallDate(string installDateString)
        {
            try
            {
                if (string.IsNullOrEmpty(installDateString))
                    return DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ssZ");

                // Intentar parsear diferentes formatos de fecha
                if (DateTime.TryParse(installDateString, out var date))
                {
                    return date.ToString("yyyy-MM-ddTHH:mm:ssZ");
                }

                // Si es un formato YYYYMMDD (común en el registro de Windows)
                if (installDateString.Length == 8 && int.TryParse(installDateString, out _))
                {
                    var year = int.Parse(installDateString.Substring(0, 4));
                    var month = int.Parse(installDateString.Substring(4, 2));
                    var day = int.Parse(installDateString.Substring(6, 2));
                    
                    var parsedDate = new DateTime(year, month, day);
                    return parsedDate.ToString("yyyy-MM-ddTHH:mm:ssZ");
                }

                return DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ssZ");
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, $"Error parseando fecha de instalación: {installDateString}");
                return DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ssZ");
            }
        }

        private string DetermineInstallMethod(ApplicationInfo app)
        {
            if (!string.IsNullOrEmpty(app.InstallationMethod))
                return app.InstallationMethod;

            // Determinar método basado en características de la aplicación
            if (!string.IsNullOrEmpty(app.ProductCode))
                return "MSI";
            
            if (app.UninstallString?.Contains("msiexec") == true)
                return "MSI";
            
            if (app.UninstallString?.Contains("setup") == true || 
                app.UninstallString?.Contains("install") == true)
                return "Setup";
            
            return "Manual";
        }

        private bool IsApplicationRunning(string applicationName)
        {
            try
            {
                var processes = System.Diagnostics.Process.GetProcesses();
                return processes.Any(p => 
                    p.ProcessName.Contains(applicationName, StringComparison.OrdinalIgnoreCase) ||
                    p.MainWindowTitle.Contains(applicationName, StringComparison.OrdinalIgnoreCase));
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, $"Error verificando si la aplicación está ejecutándose: {applicationName}");
                return false;
            }
        }

        private string CalculateApplicationHash(ApplicationInfo app)
        {
            try
            {
                if (!string.IsNullOrEmpty(app.FileHash))
                    return app.FileHash;

                if (string.IsNullOrEmpty(app.InstallLocation) || !Directory.Exists(app.InstallLocation))
                    return "no_disponible";

                // Buscar el ejecutable principal
                var exeFiles = Directory.GetFiles(app.InstallLocation, "*.exe", SearchOption.TopDirectoryOnly);
                if (exeFiles.Length > 0)
                {
                    var mainExe = exeFiles.FirstOrDefault(f => 
                        Path.GetFileNameWithoutExtension(f).Equals(app.Name, StringComparison.OrdinalIgnoreCase)) 
                        ?? exeFiles[0];

                    using var sha256 = SHA256.Create();
                    using var stream = File.OpenRead(mainExe);
                    var hash = sha256.ComputeHash(stream);
                    return Convert.ToHexString(hash).ToLowerInvariant();
                }

                return "no_disponible";
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, $"Error calculando hash de aplicación: {app.Name}");
                return "no_disponible";
            }
        }

        private string BuildNotesFromApplicationInfo(ApplicationInfo app)
        {
            var notes = new List<string>();

            if (!string.IsNullOrEmpty(app.Description))
                notes.Add($"Descripción: {app.Description}");

            if (!string.IsNullOrEmpty(app.Architecture))
                notes.Add($"Arquitectura: {app.Architecture}");

            if (!string.IsNullOrEmpty(app.Language))
                notes.Add($"Idioma: {app.Language}");

            if (app.FileSizeBytes > 0)
                notes.Add($"Tamaño: {FormatBytes(app.FileSizeBytes)}");

            if (!string.IsNullOrEmpty(app.SecurityRating) && app.SecurityRating != "Unknown")
                notes.Add($"Calificación de seguridad: {app.SecurityRating}");

            if (app.IsTrustedPublisher)
                notes.Add("Editor de confianza verificado");

            return notes.Count > 0 ? string.Join("; ", notes) : null;
        }

        private async Task ProcessServerResponse(string responseContent, ApplicationInfo app)
        {
            try
            {
                using var document = JsonDocument.Parse(responseContent);
                var root = document.RootElement;

                if (root.TryGetProperty("isApproved", out var isApprovedElement))
                {
                    var isApproved = isApprovedElement.GetBoolean();
                    _logger.LogInformation($"Estado de aprobación para {app.Name}: {(isApproved ? "Aprobado" : "Pendiente")}");
                }

                if (root.TryGetProperty("softwareId", out var softwareIdElement))
                {
                    var softwareId = softwareIdElement.GetString();
                    _logger.LogDebug($"ID de software asignado: {softwareId}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Error procesando respuesta del servidor");
            }
        }

        private static string FormatBytes(long bytes)
        {
            string[] suffixes = { "B", "KB", "MB", "GB", "TB" };
            int counter = 0;
            decimal number = bytes;
            while (Math.Round(number / 1024) >= 1)
            {
                number /= 1024;
                counter++;
            }
            return $"{number:n1} {suffixes[counter]}";
        }
    }
} 