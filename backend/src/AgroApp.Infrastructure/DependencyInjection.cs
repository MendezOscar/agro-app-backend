using AgroApp.Application.Common;
using AgroApp.Infrastructure.Identity;
using AgroApp.Infrastructure.Persistence;
using AgroApp.Infrastructure.Services;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AgroApp.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration config)
    {
        var connectionString = config.GetConnectionString("Default")
            ?? throw new InvalidOperationException("Falta ConnectionStrings:Default");

        services.AddDbContext<AppDbContext>(options =>
            options.UseNpgsql(connectionString, npgsql => npgsql.UseNetTopologySuite()));

        services.AddIdentityCore<ApplicationUser>(opt =>
            {
                opt.Password.RequiredLength = 8;
                opt.User.RequireUniqueEmail = true;
            })
            .AddRoles<IdentityRole<Guid>>()
            .AddEntityFrameworkStores<AppDbContext>();

        services.Configure<JwtOptions>(config.GetSection("Jwt"));
        services.Configure<StorageOptions>(config.GetSection("Storage"));
        services.Configure<GeminiOptions>(config.GetSection("Gemini"));
        services.AddScoped<IJwtTokenService, JwtTokenService>();
        services.AddScoped<ISpatialService, SpatialService>();
        services.AddSingleton<IStorageService, StorageService>();

        // --- IA de imágenes (cola + worker en background) ---
        services.AddSingleton<IAnalysisQueue, AnalysisQueue>();
        services.AddHttpClient<IImageAnalyzer, GeminiImageAnalyzer>();
        services.AddHostedService<ImageAnalysisWorker>();

        return services;
    }
}
