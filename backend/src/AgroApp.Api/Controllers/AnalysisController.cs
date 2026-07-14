using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record AnalysisRequest(
    AnalysisKind Kind, double? Ph, double? N, double? P, double? K,
    double? OrganicMatter, string? Texture, DateOnly? SampledAt);

public record AnalysisResponse(
    Guid Id, Guid PlotId, AnalysisKind Kind, double? Ph, double? N, double? P, double? K,
    double? OrganicMatter, string? Texture, DateOnly? SampledAt);

/// <summary>Análisis de suelo/agua por lote (etapas 1-2 del ciclo).</summary>
[Route("api")]
public class AnalysisController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public AnalysisController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    private Task<bool> OwnsPlot(Guid plotId) =>
        _db.Plots.AnyAsync(p => p.Id == plotId && p.Farm!.OrganizationId == OrgId);

    [HttpGet("plots/{plotId:guid}/analyses")]
    public async Task<ActionResult<IEnumerable<AnalysisResponse>>> List(Guid plotId)
    {
        if (!await OwnsPlot(plotId)) return NotFound();
        var items = await _db.Analyses.Where(a => a.PlotId == plotId)
            .OrderByDescending(a => a.SampledAt).ToListAsync();
        return Ok(items.Select(ToResponse));
    }

    [HttpPost("plots/{plotId:guid}/analyses")]
    public async Task<ActionResult<AnalysisResponse>> Create(Guid plotId, AnalysisRequest req)
    {
        if (!await OwnsPlot(plotId)) return NotFound();
        var a = new Analysis
        {
            PlotId = plotId,
            Kind = req.Kind,
            Ph = req.Ph,
            N = req.N,
            P = req.P,
            K = req.K,
            OrganicMatter = req.OrganicMatter,
            Texture = req.Texture,
            SampledAt = req.SampledAt
        };
        _db.Analyses.Add(a);
        await _db.SaveChangesAsync();
        return Ok(ToResponse(a));
    }

    [HttpDelete("analyses/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var a = await _db.Analyses.FirstOrDefaultAsync(x => x.Id == id &&
            _db.Plots.Any(p => p.Id == x.PlotId && p.Farm!.OrganizationId == OrgId));
        if (a is null) return NotFound();
        _db.Analyses.Remove(a);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static AnalysisResponse ToResponse(Analysis a) => new(
        a.Id, a.PlotId, a.Kind, a.Ph, a.N, a.P, a.K, a.OrganicMatter, a.Texture, a.SampledAt);
}
