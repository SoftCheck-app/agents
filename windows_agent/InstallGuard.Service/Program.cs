using InstallGuard.Service.Services;
using Microsoft.Extensions.Hosting.WindowsServices;

var builder = Host.CreateDefaultBuilder(args)
    .UseWindowsService(options =>
    {
        options.ServiceName = "InstallGuard Service";
    })
    .ConfigureLogging(logging =>
    {
        // Configurar logging para servicio de Windows
        logging.ClearProviders();
        logging.AddConsole();
        logging.AddEventLog(eventLogSettings =>
        {
            eventLogSettings.SourceName = "InstallGuard Service";
        });
    })
    .ConfigureServices((context, services) =>
    {
        // Registrar servicios
        services.AddHttpClient();
        services.AddSingleton<IBackendService, BackendService>();
        services.AddSingleton<IFileCleanupService, FileCleanupService>();
        services.AddSingleton<INotificationService, NotificationService>();
        services.AddSingleton<ISoftwareReportingService, SoftwareReportingService>();
        services.AddSingleton<IInstallationMonitorService, InstallationMonitorService>();
        services.AddHostedService<FileCleanupService>(sp => (FileCleanupService)sp.GetRequiredService<IFileCleanupService>());
        
        // Solo registrar DriverService si está habilitado en configuración
        var enableDriver = context.Configuration.GetValue<bool>("Features:EnableDriver", true);
        if (enableDriver)
        {
            services.AddHostedService<DriverService>();
        }
        
        services.AddHostedService<AgentPingService>();
        services.AddHostedService<InstallationMonitorService>(sp => (InstallationMonitorService)sp.GetRequiredService<IInstallationMonitorService>());
        
        // DESACTIVADO: Servicio de prueba (solo para desarrollo)
        // services.AddHostedService<InstallationTestService>();
    });

var host = builder.Build();

// Log de inicio del servicio
var logger = host.Services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("InstallGuard Service iniciando...");

try
{
    await host.RunAsync();
}
catch (Exception ex)
{
    logger.LogCritical(ex, "Error crítico en InstallGuard Service");
    throw;
} 