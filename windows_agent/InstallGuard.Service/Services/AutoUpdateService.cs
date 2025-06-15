using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using InstallGuard.Common.Models;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;

namespace InstallGuard.Service.Services;

public class AutoUpdateService : BackgroundService, IAutoUpdateService
{
    private readonly ILogger<AutoUpdateService> _logger;
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly IHostApplicationLifetime _applicationLifetime;
    private readonly string _updateCheckUrl;
    private readonly TimeSpan _checkInterval;
    
    public AutoUpdateService(
        ILogger<AutoUpdateService> logger,
        HttpClient httpClient,
        IConfiguration configuration,
        IHostApplicationLifetime applicationLifetime)
    {
        _logger = logger;
        _httpClient = httpClient;
        _configuration = configuration;
        _applicationLifetime = applicationLifetime;
        
        // Configurar URL y intervalo desde configuración
        _updateCheckUrl = configuration["AutoUpdate:UpdateCheckUrl"] ?? "https://agents.softcheck.app/windows-agent/latest-version";
        var intervalMinutes = configuration.GetValue<int>("AutoUpdate:CheckIntervalMinutes", 30);
        _checkInterval = TimeSpan.FromMinutes(intervalMinutes);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("AutoUpdateService iniciado. Verificando actualizaciones cada {Interval} minutos", _checkInterval.TotalMinutes);
        _logger.LogInformation("URL de verificación: {Url}", _updateCheckUrl);
        
        // Verificar al inicio
        await CheckForUpdatesAsync();
        
        // Verificar cada intervalo configurado
        using var timer = new PeriodicTimer(_checkInterval);
        
        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                await CheckForUpdatesAsync();
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("AutoUpdateService detenido");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error en AutoUpdateService");
        }
    }

    public async Task CheckForUpdatesAsync()
    {
        try
        {
            _logger.LogInformation("Verificando actualizaciones...");
            
            var currentVersion = await GetCurrentVersionAsync();
            _logger.LogInformation("Versión actual: {CurrentVersion}", currentVersion);
            
            var response = await _httpClient.GetAsync(_updateCheckUrl);
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("No se pudo verificar actualizaciones. Status: {StatusCode}", response.StatusCode);
                return;
            }
            
            var jsonContent = await response.Content.ReadAsStringAsync();
            var versionResponse = JsonSerializer.Deserialize<VersionResponse>(jsonContent, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            
            if (versionResponse == null || string.IsNullOrEmpty(versionResponse.Version))
            {
                _logger.LogWarning("Respuesta de versión inválida del servidor");
                return;
            }
            
            _logger.LogInformation("Versión disponible en servidor: {ServerVersion}", versionResponse.Version);
            
            var currentVersionInfo = new VersionInfo(currentVersion);
            var serverVersionInfo = new VersionInfo(versionResponse.Version);
            
            if (serverVersionInfo.IsNewerThan(currentVersionInfo))
            {
                _logger.LogInformation("Nueva versión disponible: {NewVersion}. Iniciando actualización...", versionResponse.Version);
                await PerformUpdateAsync(versionResponse);
            }
            else
            {
                _logger.LogInformation("El agente está actualizado");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al verificar actualizaciones");
        }
    }

    public async Task<bool> IsUpdateAvailableAsync()
    {
        try
        {
            var currentVersion = await GetCurrentVersionAsync();
            var response = await _httpClient.GetAsync(_updateCheckUrl);
            
            if (!response.IsSuccessStatusCode)
                return false;
            
            var jsonContent = await response.Content.ReadAsStringAsync();
            var versionResponse = JsonSerializer.Deserialize<VersionResponse>(jsonContent, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            
            if (versionResponse == null || string.IsNullOrEmpty(versionResponse.Version))
                return false;
            
            var currentVersionInfo = new VersionInfo(currentVersion);
            var serverVersionInfo = new VersionInfo(versionResponse.Version);
            
            return serverVersionInfo.IsNewerThan(currentVersionInfo);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al verificar si hay actualizaciones disponibles");
            return false;
        }
    }

    public async Task<string> GetCurrentVersionAsync()
    {
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            return version != null ? $"{version.Major}.{version.Minor}.{version.Build}" : "1.0.0";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al obtener la versión actual");
            return "1.0.0";
        }
    }

    private async Task PerformUpdateAsync(VersionResponse versionResponse)
    {
        try
        {
            _logger.LogInformation("Descargando nueva versión desde: {Url}", versionResponse.Url);
            
            // Crear directorio temporal para la actualización
            var tempDir = Path.Combine(Path.GetTempPath(), "InstallGuard_Update");
            Directory.CreateDirectory(tempDir);
            
            var tempFilePath = Path.Combine(tempDir, "InstallGuard.Service.exe");
            
            // Descargar nueva versión
            var downloadResponse = await _httpClient.GetAsync(versionResponse.Url);
            downloadResponse.EnsureSuccessStatusCode();
            
            await using var fileStream = File.Create(tempFilePath);
            await downloadResponse.Content.CopyToAsync(fileStream);
            
            _logger.LogInformation("Descarga completada. Preparando actualización...");
            
            // Obtener ruta del ejecutable actual
            var currentExecutablePath = Process.GetCurrentProcess().MainModule?.FileName;
            if (string.IsNullOrEmpty(currentExecutablePath))
            {
                _logger.LogError("No se pudo obtener la ruta del ejecutable actual");
                return;
            }
            
            // Crear script de actualización
            var updateScriptPath = Path.Combine(tempDir, "update.bat");
            var updateScript = $@"@echo off
echo Actualizando InstallGuard Agent...
timeout /t 5 /nobreak >nul
taskkill /f /im ""InstallGuard.Service.exe"" >nul 2>&1
timeout /t 2 /nobreak >nul
copy ""{tempFilePath}"" ""{currentExecutablePath}"" >nul
if %errorlevel% equ 0 (
    echo Actualización completada exitosamente
    sc start ""InstallGuard Agent""
) else (
    echo Error en la actualización
)
timeout /t 2 /nobreak >nul
rd /s /q ""{tempDir}"" >nul 2>&1
del ""%~f0"" >nul 2>&1
";
            
            await File.WriteAllTextAsync(updateScriptPath, updateScript);
            
            _logger.LogInformation("Ejecutando actualización...");
            
            // Ejecutar script de actualización
            var processInfo = new ProcessStartInfo
            {
                FileName = updateScriptPath,
                UseShellExecute = true,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            
            Process.Start(processInfo);
            
            // Detener el servicio actual para permitir la actualización
            _logger.LogInformation("Deteniendo servicio para actualización...");
            _applicationLifetime.StopApplication();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error durante la actualización");
        }
    }
} 