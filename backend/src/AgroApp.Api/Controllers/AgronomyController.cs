using AgroApp.Application.Common;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

/// <summary>Indicadores agronómicos (suelo, riego, GDD, riesgo) por ciclo, vía Open-Meteo.</summary>
[Route("api")]
public class AgronomyController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly IAgronomyService _agronomy;

    public AgronomyController(AppDbContext db, IAgronomyService agronomy, ICurrentUser me) : base(me)
    {
        _db = db;
        _agronomy = agronomy;
    }

    [HttpGet("cycles/{cycleId:guid}/agronomy")]
    public async Task<ActionResult<AgronomyResult>> Get(Guid cycleId, CancellationToken ct)
    {
        var cycle = await _db.CropCycles
            .Include(c => c.Plot!).ThenInclude(p => p.Farm!)
            .FirstOrDefaultAsync(c => c.Id == cycleId && c.Plot!.Farm!.OrganizationId == OrgId, ct);
        if (cycle is null) return NotFound();

        var loc = cycle.Plot?.Farm?.Location;
        if (loc is null)
            return Ok(new AgronomyResult(
                Array.Empty<SoilLayer>(), null, null, null, "",
                "La finca no tiene ubicación. Asigna coordenadas a la finca para ver los indicadores agronómicos."));

        var start = cycle.ActualStart ?? cycle.PlannedStart;
        var result = await _agronomy.GetAsync(loc.Y, loc.X, start, cycle.Crop, ct);
        return Ok(result);
    }
}
