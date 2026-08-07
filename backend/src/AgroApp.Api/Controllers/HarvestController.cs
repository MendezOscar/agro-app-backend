using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record HarvestStepResponse(
    Guid Id, int Order, string Name, int Status, DateTimeOffset? CompletedAt,
    double? QtyIn, double? QtyOut, string? Unit, string? Notes);
public record HarvestStepsResponse(Guid CycleId, string Crop, int Done, int Total, IEnumerable<HarvestStepResponse> Steps);
public record HarvestStepUpdate(int Status, DateTimeOffset? CompletedAt, double? QtyIn, double? QtyOut, string? Notes);
public record HarvestTemplateResponse(string Crop, IEnumerable<string> Steps, bool IsCustom);
public record HarvestTemplateUpdate(IEnumerable<string> Steps);

/// <summary>Proceso de cosecha por pasos, configurable por organización (cliente) y cultivo.</summary>
[Route("api")]
public class HarvestController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public HarvestController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    private IQueryable<CropCycle> OrgCycles =>
        _db.CropCycles.Where(c => c.Plot!.Farm!.OrganizationId == OrgId);

    // Pasos por defecto por cultivo (orientativos; el cliente puede personalizarlos).
    private static string[] DefaultSteps(string crop)
    {
        var c = (crop ?? "").ToLowerInvariant();
        if (c.Contains("café") || c.Contains("cafe") || c.Contains("coffee"))
            return new[] { "Corte", "Despulpe", "Fermentado", "Lavado", "Secado", "Trilla", "Tostado", "Empacado" };
        if (c.Contains("maíz") || c.Contains("maiz") || c.Contains("corn"))
            return new[] { "Cosecha", "Secado", "Desgrane", "Limpieza", "Almacenado" };
        if (c.Contains("arroz") || c.Contains("rice"))
            return new[] { "Cosecha", "Secado", "Descascarado", "Pulido", "Almacenado" };
        if (c.Contains("frijol") || c.Contains("fríjol") || c.Contains("bean"))
            return new[] { "Arranque", "Secado", "Aporreo", "Limpieza", "Almacenado" };
        if (c.Contains("papa") || c.Contains("patata") || c.Contains("potato"))
            return new[] { "Cosecha", "Curado", "Clasificado", "Almacenado" };
        if (c.Contains("trigo") || c.Contains("wheat"))
            return new[] { "Cosecha", "Trilla", "Secado", "Almacenado" };
        if (c.Contains("tomate") || c.Contains("tomato") || c.Contains("hortaliza"))
            return new[] { "Corte", "Selección", "Empacado", "Enfriado" };
        return new[] { "Cosecha", "Secado", "Limpieza", "Almacenado", "Empacado" };
    }

    private async Task<string[]> ResolveTemplateAsync(string crop)
    {
        var custom = await _db.HarvestStepTemplates
            .FirstOrDefaultAsync(t => t.OrganizationId == OrgId && t.Crop == crop);
        if (custom is not null && custom.Steps.Count > 0) return custom.Steps.ToArray();
        return DefaultSteps(crop);
    }

    private static HarvestStepResponse ToResponse(HarvestStep s) => new(
        s.Id, s.Order, s.Name, (int)s.Status, s.CompletedAt, s.QtyIn, s.QtyOut, s.Unit, s.Notes);

    // GET pasos del ciclo (materializa desde la plantilla resuelta si aún no existen).
    [HttpGet("cycles/{cycleId:guid}/harvest-steps")]
    public async Task<ActionResult<HarvestStepsResponse>> Steps(Guid cycleId)
    {
        var cycle = await OrgCycles.FirstOrDefaultAsync(c => c.Id == cycleId);
        if (cycle is null) return NotFound();

        var steps = await _db.HarvestSteps.Where(s => s.CropCycleId == cycleId)
            .OrderBy(s => s.Order).ToListAsync();

        if (steps.Count == 0)
        {
            var names = await ResolveTemplateAsync(cycle.Crop);
            steps = names.Select((n, i) => new HarvestStep
            {
                CropCycleId = cycleId, Order = i, Name = n, Status = StageStatus.Pending, Unit = "kg",
            }).ToList();
            _db.HarvestSteps.AddRange(steps);
            await _db.SaveChangesAsync();
        }

        var done = steps.Count(s => s.Status == StageStatus.Completed);
        return Ok(new HarvestStepsResponse(cycleId, cycle.Crop, done, steps.Count, steps.Select(ToResponse)));
    }

    [HttpPut("harvest-steps/{stepId:guid}")]
    public async Task<ActionResult<HarvestStepResponse>> UpdateStep(Guid stepId, HarvestStepUpdate req)
    {
        var step = await _db.HarvestSteps
            .FirstOrDefaultAsync(s => s.Id == stepId &&
                OrgCycles.Any(c => c.Id == s.CropCycleId));
        if (step is null) return NotFound();

        step.Status = (StageStatus)req.Status;
        step.QtyIn = req.QtyIn;
        step.QtyOut = req.QtyOut;
        step.Notes = req.Notes;
        step.CompletedAt = step.Status == StageStatus.Completed ? (req.CompletedAt ?? DateTimeOffset.UtcNow) : req.CompletedAt;
        step.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(ToResponse(step));
    }

    // GET plantilla resuelta para un cultivo (default del cultivo o el override de la org).
    [HttpGet("harvest-templates/{crop}")]
    public async Task<ActionResult<HarvestTemplateResponse>> GetTemplate(string crop)
    {
        var custom = await _db.HarvestStepTemplates
            .FirstOrDefaultAsync(t => t.OrganizationId == OrgId && t.Crop == crop);
        var steps = custom is not null && custom.Steps.Count > 0 ? custom.Steps : DefaultSteps(crop).ToList();
        return Ok(new HarvestTemplateResponse(crop, steps, custom is not null));
    }

    [HttpPut("harvest-templates/{crop}")]
    public async Task<ActionResult<HarvestTemplateResponse>> SaveTemplate(string crop, HarvestTemplateUpdate req)
    {
        var steps = req.Steps.Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
        if (steps.Count == 0) return BadRequest("La plantilla debe tener al menos un paso.");

        var t = await _db.HarvestStepTemplates
            .FirstOrDefaultAsync(x => x.OrganizationId == OrgId && x.Crop == crop);
        if (t is null)
        {
            t = new HarvestStepTemplate { OrganizationId = OrgId, Crop = crop, Steps = steps };
            _db.HarvestStepTemplates.Add(t);
        }
        else
        {
            t.Steps = steps;
            t.UpdatedAt = DateTimeOffset.UtcNow;
        }
        await _db.SaveChangesAsync();
        return Ok(new HarvestTemplateResponse(crop, steps, true));
    }

    [HttpDelete("harvest-templates/{crop}")]
    public async Task<ActionResult<HarvestTemplateResponse>> ResetTemplate(string crop)
    {
        var t = await _db.HarvestStepTemplates
            .FirstOrDefaultAsync(x => x.OrganizationId == OrgId && x.Crop == crop);
        if (t is not null) { _db.HarvestStepTemplates.Remove(t); await _db.SaveChangesAsync(); }
        return Ok(new HarvestTemplateResponse(crop, DefaultSteps(crop).ToList(), false));
    }
}
