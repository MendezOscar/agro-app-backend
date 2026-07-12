using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AgroApp.Infrastructure.Services;

/// <summary>
/// Procesa la cola de observaciones: descarga la foto de S3, la envía a la IA de visión
/// y persiste un ImageAnalysis. Corre en segundo plano para no bloquear la subida/sync.
/// </summary>
public class ImageAnalysisWorker : BackgroundService
{
    private readonly IAnalysisQueue _queue;
    private readonly IServiceScopeFactory _scopes;
    private readonly IStorageService _storage;
    private readonly IImageAnalyzer _analyzer;
    private readonly ILogger<ImageAnalysisWorker> _log;

    public ImageAnalysisWorker(
        IAnalysisQueue queue, IServiceScopeFactory scopes, IStorageService storage,
        IImageAnalyzer analyzer, ILogger<ImageAnalysisWorker> log)
    {
        _queue = queue;
        _scopes = scopes;
        _storage = storage;
        _analyzer = analyzer;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var obsId in _queue.DequeueAllAsync(stoppingToken))
        {
            try
            {
                await ProcessAsync(obsId, stoppingToken);
            }
            catch (Exception ex)
            {
                _log.LogError(ex, "Fallo al analizar la observación {ObsId}", obsId);
            }
        }
    }

    private async Task ProcessAsync(Guid obsId, CancellationToken ct)
    {
        using var scope = _scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var obs = await db.Observations.FirstOrDefaultAsync(o => o.Id == obsId, ct);
        if (obs?.PhotoKey is null) return;

        var crop = await db.CropCycles.Where(c => c.Id == obs.CropCycleId)
            .Select(c => c.Crop).FirstOrDefaultAsync(ct) ?? "desconocido";

        var bytes = await _storage.DownloadAsync(obs.PhotoKey, ct);
        var contentType = obs.PhotoKey.EndsWith(".png") ? "image/png" : "image/jpeg";
        var result = await _analyzer.AnalyzeAsync(bytes, contentType, crop, ct);

        var analysis = await db.ImageAnalyses.FirstOrDefaultAsync(a => a.ObservationId == obsId, ct);
        if (analysis is null)
        {
            analysis = new ImageAnalysis { ObservationId = obsId };
            db.ImageAnalyses.Add(analysis);
        }
        analysis.Diagnosis = result.RawJson;
        analysis.Severity = result.Severity;
        analysis.Confidence = result.Confidence;
        analysis.Recommendations = result.Recommendations;
        analysis.AnalyzedAt = DateTimeOffset.UtcNow;
        analysis.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);
        _log.LogInformation("Observación {ObsId} analizada: {Sev}", obsId, result.Severity);
    }
}
