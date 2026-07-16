using AgroApp.Api.Contracts;
using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record ObservationRequest(Guid? Id, double[]? Location, string? Note);
public record ImageAnalysisResponse(
    string? Severity, double? Confidence, string? Recommendations, string? Diagnosis, DateTimeOffset? AnalyzedAt);
public record ObservationResponse(
    Guid Id, Guid CropCycleId, Guid CreatedByUserId, double[]? Location, string? Note,
    string? PhotoUrl, DateTimeOffset CreatedAt, ImageAnalysisResponse? Analysis);

[Route("api")]
public class ObservationsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly IStorageService _storage;
    private readonly IAnalysisQueue _analysisQueue;

    public ObservationsController(
        AppDbContext db, ICurrentUser me, IStorageService storage, IAnalysisQueue analysisQueue) : base(me)
    {
        _db = db;
        _storage = storage;
        _analysisQueue = analysisQueue;
    }

    private Task<bool> OwnsCycle(Guid cycleId) =>
        _db.CropCycles.AnyAsync(c => c.Id == cycleId && c.Plot!.Farm!.OrganizationId == OrgId);

    private Task<Observation?> Find(Guid id) =>
        _db.Observations.FirstOrDefaultAsync(o => o.Id == id &&
            _db.CropCycles.Any(c => c.Id == o.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId));

    [HttpGet("cycles/{cycleId:guid}/observations")]
    public async Task<ActionResult<IEnumerable<ObservationResponse>>> List(Guid cycleId)
    {
        if (!await OwnsCycle(cycleId)) return NotFound();
        var obs = await _db.Observations.Include(o => o.ImageAnalysis)
            .Where(o => o.CropCycleId == cycleId)
            .OrderByDescending(o => o.CreatedAt).ToListAsync();
        return Ok(obs.Select(ToResponse));
    }

    [HttpPost("cycles/{cycleId:guid}/observations")]
    public async Task<ActionResult<ObservationResponse>> Create(Guid cycleId, ObservationRequest req)
    {
        if (!await OwnsCycle(cycleId)) return NotFound();
        var obs = new Observation
        {
            Id = req.Id ?? Guid.NewGuid(),   // acepta el Id generado en cliente (offline)
            CropCycleId = cycleId,
            CreatedByUserId = Me.UserId ?? Guid.Empty,
            Location = Geo.ToPoint(req.Location),
            Note = req.Note
        };
        _db.Observations.Add(obs);
        await _db.SaveChangesAsync();
        return Ok(ToResponse(obs));
    }

    /// <summary>Sube la foto de la observación a S3/MinIO y guarda su clave.</summary>
    [HttpPost("observations/{id:guid}/photo")]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult<ObservationResponse>> UploadPhoto(Guid id, IFormFile file)
    {
        var obs = await Find(id);
        if (obs is null) return NotFound();
        if (file.Length == 0) return BadRequest(new { message = "Archivo vacío." });

        var ext = Path.GetExtension(file.FileName);
        var key = $"observations/{id}{ext}";
        await using var stream = file.OpenReadStream();
        await _storage.UploadAsync(stream, key, file.ContentType);

        obs.PhotoKey = key;
        obs.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();

        _analysisQueue.Enqueue(obs.Id);   // dispara el análisis IA en background
        return Ok(ToResponse(obs));
    }

    /// <summary>Analiza la foto de la observación de forma sincrónica y devuelve el resultado
    /// (o el error). Útil para re-analizar y diagnosticar la integración de IA.</summary>
    [HttpPost("observations/{id:guid}/analyze")]
    public async Task<IActionResult> AnalyzeNow(
        Guid id, [FromServices] IImageAnalyzer analyzer)
    {
        var obs = await Find(id);
        if (obs?.PhotoKey is null) return NotFound(new { message = "La observación no tiene foto." });

        try
        {
            var crop = await _db.CropCycles.Where(c => c.Id == obs.CropCycleId)
                .Select(c => c.Crop).FirstOrDefaultAsync() ?? "desconocido";
            var bytes = await _storage.DownloadAsync(obs.PhotoKey);
            var contentType = obs.PhotoKey.EndsWith(".png") ? "image/png" : "image/jpeg";
            var result = await analyzer.AnalyzeAsync(bytes, contentType, crop);

            var analysis = await _db.ImageAnalyses.FirstOrDefaultAsync(a => a.ObservationId == id);
            if (analysis is null)
            {
                analysis = new ImageAnalysis { ObservationId = id };
                _db.ImageAnalyses.Add(analysis);
            }
            analysis.Diagnosis = result.RawJson;
            analysis.Severity = result.Severity;
            analysis.Confidence = result.Confidence;
            analysis.Recommendations = result.Recommendations;
            analysis.AnalyzedAt = DateTimeOffset.UtcNow;
            analysis.UpdatedAt = DateTimeOffset.UtcNow;
            await _db.SaveChangesAsync();

            return Ok(new ImageAnalysisResponse(result.Severity, result.Confidence, result.Recommendations, result.Diagnosis, analysis.AnalyzedAt));
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = ex.Message, inner = ex.InnerException?.Message });
        }
    }

    private ObservationResponse ToResponse(Observation o) => new(
        o.Id, o.CropCycleId, o.CreatedByUserId, Geo.FromPoint(o.Location), o.Note,
        o.PhotoKey is null ? null : _storage.GetPresignedUrl(o.PhotoKey, TimeSpan.FromHours(1)),
        o.CreatedAt,
        o.ImageAnalysis is null ? null : new ImageAnalysisResponse(
            o.ImageAnalysis.Severity, o.ImageAnalysis.Confidence, o.ImageAnalysis.Recommendations,
            o.ImageAnalysis.Diagnosis, o.ImageAnalysis.AnalyzedAt));
}
