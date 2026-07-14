using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record PhenologyRequest(
    DateOnly RecordedAt, PhenoStage Stage, double? PlantHeightCm,
    double? PestIncidencePct, double? DiseaseIncidencePct, string? Notes);

public record PhenologyResponse(
    Guid Id, Guid CropCycleId, DateOnly RecordedAt, PhenoStage Stage, double? PlantHeightCm,
    double? PestIncidencePct, double? DiseaseIncidencePct, string? Notes);

/// <summary>Registros fenológicos de la etapa de monitoreo (etapa 5) por ciclo.</summary>
[Route("api")]
public class PhenologyController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public PhenologyController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    private Task<bool> OwnsCycle(Guid cycleId) =>
        _db.CropCycles.AnyAsync(c => c.Id == cycleId && c.Plot!.Farm!.OrganizationId == OrgId);

    [HttpGet("cycles/{cycleId:guid}/phenology")]
    public async Task<ActionResult<IEnumerable<PhenologyResponse>>> List(Guid cycleId)
    {
        if (!await OwnsCycle(cycleId)) return NotFound();
        var items = await _db.PhenologyRecords.Where(p => p.CropCycleId == cycleId)
            .OrderByDescending(p => p.RecordedAt).ToListAsync();
        return Ok(items.Select(ToResponse));
    }

    [HttpPost("cycles/{cycleId:guid}/phenology")]
    public async Task<ActionResult<PhenologyResponse>> Create(Guid cycleId, PhenologyRequest req)
    {
        if (!await OwnsCycle(cycleId)) return NotFound();
        var rec = new PhenologyRecord
        {
            CropCycleId = cycleId,
            RecordedAt = req.RecordedAt,
            Stage = req.Stage,
            PlantHeightCm = req.PlantHeightCm,
            PestIncidencePct = req.PestIncidencePct,
            DiseaseIncidencePct = req.DiseaseIncidencePct,
            Notes = req.Notes
        };
        _db.PhenologyRecords.Add(rec);
        await _db.SaveChangesAsync();
        return Ok(ToResponse(rec));
    }

    [HttpDelete("phenology/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var rec = await _db.PhenologyRecords.FirstOrDefaultAsync(p => p.Id == id &&
            _db.CropCycles.Any(c => c.Id == p.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId));
        if (rec is null) return NotFound();
        _db.PhenologyRecords.Remove(rec);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static PhenologyResponse ToResponse(PhenologyRecord p) => new(
        p.Id, p.CropCycleId, p.RecordedAt, p.Stage, p.PlantHeightCm,
        p.PestIncidencePct, p.DiseaseIncidencePct, p.Notes);
}
