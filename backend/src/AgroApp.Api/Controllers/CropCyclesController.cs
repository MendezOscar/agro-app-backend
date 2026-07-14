using AgroApp.Api.Contracts;
using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record CostByStage(StageKind? Kind, decimal Total);
public record CycleReportResponse(
    Guid Id, string Crop, string? Variety, CropCycleStatus Status, string? PlotName, decimal AreaHa,
    decimal YieldKg, decimal YieldPerHa, string? Quality, decimal PostHarvestLossKg, decimal LossPct,
    decimal TotalCost, decimal RevenueEst, decimal Margin, decimal CostPerKg,
    IEnumerable<CostByKind> CostByKind, IEnumerable<CostByStage> CostByStage);

[Route("api")]
public class CropCyclesController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public CropCyclesController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    // Ciclos accesibles: los de lotes de fincas de la organización.
    private IQueryable<CropCycle> OrgCycles =>
        _db.CropCycles.Where(c => c.Plot!.Farm!.OrganizationId == OrgId);

    [HttpGet("plots/{plotId:guid}/cycles")]
    public async Task<ActionResult<IEnumerable<CycleResponse>>> ListByPlot(Guid plotId)
    {
        var cycles = await OrgCycles.Where(c => c.PlotId == plotId)
            .OrderByDescending(c => c.CreatedAt).ToListAsync();
        return Ok(cycles.Select(c => ToResponse(c, includeStages: false)));
    }

    [HttpGet("cycles/{id:guid}")]
    public async Task<ActionResult<CycleResponse>> Get(Guid id)
    {
        var cycle = await OrgCycles.Include(c => c.Stages.OrderBy(s => s.Kind))
            .FirstOrDefaultAsync(c => c.Id == id);
        return cycle is null ? NotFound() : Ok(ToResponse(cycle, includeStages: true));
    }

    /// <summary>Reporte consolidado del ciclo: costos, rendimiento y márgenes.</summary>
    [HttpGet("cycles/{id:guid}/report")]
    public async Task<ActionResult<CycleReportResponse>> Report(Guid id)
    {
        var cycle = await OrgCycles.Include(c => c.Plot).FirstOrDefaultAsync(c => c.Id == id);
        if (cycle is null) return NotFound();

        var byKind = await _db.CostEntries.Where(c => c.CropCycleId == id)
            .GroupBy(c => c.Kind)
            .Select(g => new CostByKind(g.Key, g.Sum(x => x.Total)))
            .ToListAsync();
        var totalCost = byKind.Sum(k => k.Total);

        // Costo por etapa: se agrupa por StageId y se mapea a su tipo de etapa.
        var stageKinds = await _db.Stages.Where(s => s.CropCycleId == id)
            .ToDictionaryAsync(s => s.Id, s => s.Kind);
        var byStageRaw = await _db.CostEntries.Where(c => c.CropCycleId == id)
            .GroupBy(c => c.StageId)
            .Select(g => new { g.Key, Total = g.Sum(x => x.Total) })
            .ToListAsync();
        var byStage = byStageRaw
            .Select(x => new CostByStage(
                x.Key is { } sid && stageKinds.TryGetValue(sid, out var k) ? k : (StageKind?)null,
                x.Total))
            .ToList();

        var hr = await _db.HarvestResults.FirstOrDefaultAsync(h => h.CropCycleId == id);
        var yieldKg = (decimal)(hr?.YieldKg ?? cycle.YieldKg ?? 0);
        var lossKg = (decimal)(hr?.PostHarvestLossKg ?? 0);
        var revenue = hr?.RevenueEst ?? 0m;
        var areaHa = (decimal)(cycle.Plot?.AreaHa ?? 0);

        return Ok(new CycleReportResponse(
            cycle.Id, cycle.Crop, cycle.Variety, cycle.Status, cycle.Plot?.Name, areaHa,
            yieldKg, areaHa > 0 ? Math.Round(yieldKg / areaHa, 2) : 0,
            hr?.Quality, lossKg, yieldKg > 0 ? Math.Round(lossKg / yieldKg * 100, 1) : 0,
            totalCost, revenue, revenue - totalCost,
            yieldKg > 0 ? Math.Round(totalCost / yieldKg, 2) : 0,
            byKind, byStage));
    }

    /// <summary>Crea un ciclo de cosecha y sus 8 etapas en estado Pending.</summary>
    [HttpPost("cycles")]
    public async Task<ActionResult<CycleResponse>> Create(CreateCycleRequest req)
    {
        var ownsPlot = await _db.Plots.AnyAsync(p => p.Id == req.PlotId && p.Farm!.OrganizationId == OrgId);
        if (!ownsPlot) return NotFound(new { message = "Lote no encontrado." });

        var cycle = new CropCycle
        {
            PlotId = req.PlotId,
            Crop = req.Crop,
            Variety = req.Variety,
            PlannedStart = req.PlannedStart,
            PlannedEnd = req.PlannedEnd,
            Status = CropCycleStatus.Planned
        };
        foreach (var kind in Enum.GetValues<StageKind>())
            cycle.Stages.Add(new Stage { Kind = kind, Status = StageStatus.Pending });

        _db.CropCycles.Add(cycle);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = cycle.Id }, ToResponse(cycle, includeStages: true));
    }

    /// <summary>Avanza el estado de una etapa; marca inicio real del ciclo al arrancar la primera.</summary>
    [HttpPut("stages/{stageId:guid}")]
    public async Task<ActionResult<StageResponse>> AdvanceStage(Guid stageId, AdvanceStageRequest req)
    {
        var stage = await _db.Stages
            .FirstOrDefaultAsync(s => s.Id == stageId &&
                _db.CropCycles.Any(c => c.Id == s.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId));
        if (stage is null) return NotFound();

        stage.Status = req.Status;
        stage.Notes = req.Notes ?? stage.Notes;
        stage.UpdatedAt = DateTimeOffset.UtcNow;
        if (req.Status == StageStatus.InProgress && stage.StartedAt is null)
            stage.StartedAt = DateTimeOffset.UtcNow;
        if (req.Status == StageStatus.Completed)
            stage.CompletedAt = DateTimeOffset.UtcNow;

        var cycle = await _db.CropCycles.FirstAsync(c => c.Id == stage.CropCycleId);
        if (cycle.Status == CropCycleStatus.Planned && req.Status == StageStatus.InProgress)
        {
            cycle.Status = CropCycleStatus.Active;
            cycle.ActualStart ??= DateOnly.FromDateTime(DateTime.UtcNow);
        }

        await _db.SaveChangesAsync();
        return Ok(ToStageResponse(stage));
    }

    /// <summary>Cierra el ciclo y registra el resultado de cosecha (con costo total acumulado).</summary>
    [HttpPost("cycles/{id:guid}/close")]
    public async Task<ActionResult<CycleResponse>> Close(Guid id, CloseCycleRequest req)
    {
        var cycle = await OrgCycles.FirstOrDefaultAsync(c => c.Id == id);
        if (cycle is null) return NotFound();

        var totalCost = await _db.CostEntries.Where(c => c.CropCycleId == id).SumAsync(c => (decimal?)c.Total) ?? 0m;

        cycle.Status = CropCycleStatus.Closed;
        cycle.YieldKg = req.YieldKg;
        cycle.ActualEnd = DateOnly.FromDateTime(DateTime.UtcNow);
        cycle.UpdatedAt = DateTimeOffset.UtcNow;

        var existing = await _db.HarvestResults.FirstOrDefaultAsync(h => h.CropCycleId == id);
        if (existing is null)
        {
            _db.HarvestResults.Add(new HarvestResult
            {
                CropCycleId = id,
                YieldKg = req.YieldKg,
                Quality = req.Quality,
                PostHarvestLossKg = req.PostHarvestLossKg,
                RevenueEst = req.RevenueEst,
                TotalCost = totalCost,
                Notes = req.Notes
            });
        }
        else
        {
            existing.YieldKg = req.YieldKg;
            existing.Quality = req.Quality;
            existing.PostHarvestLossKg = req.PostHarvestLossKg;
            existing.RevenueEst = req.RevenueEst;
            existing.TotalCost = totalCost;
            existing.Notes = req.Notes;
        }

        await _db.SaveChangesAsync();
        return Ok(ToResponse(cycle, includeStages: false));
    }

    private static CycleResponse ToResponse(CropCycle c, bool includeStages) => new(
        c.Id, c.PlotId, c.Crop, c.Variety, c.Status,
        c.PlannedStart, c.ActualStart, c.PlannedEnd, c.ActualEnd, c.YieldKg,
        includeStages ? c.Stages.OrderBy(s => s.Kind).Select(ToStageResponse) : null);

    private static StageResponse ToStageResponse(Stage s) =>
        new(s.Id, s.Kind, s.Status, s.StartedAt, s.CompletedAt, s.Notes);
}
