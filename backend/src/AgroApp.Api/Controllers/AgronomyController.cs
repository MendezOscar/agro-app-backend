using AgroApp.Application.Common;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

/// <summary>Contexto para calcular indicadores agronómicos en el cliente (que llama a Open-Meteo
/// desde su propia IP, evitando el límite por IP compartida de Render).</summary>
public record AgronomyContext(
    double? Lat, double? Lng, DateOnly? CycleStart, string Crop, double BaseTempC, string? Message);

[Route("api")]
public class AgronomyController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public AgronomyController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    // Temperatura base para GDD por cultivo (°C). Default 10.
    private static double BaseTemp(string crop)
    {
        var c = (crop ?? "").ToLowerInvariant();
        if (c.Contains("arroz") || c.Contains("rice")) return 12;
        if (c.Contains("papa") || c.Contains("patata") || c.Contains("potato")) return 7;
        if (c.Contains("trigo") || c.Contains("wheat")) return 4;
        return 10; // café, maíz, frijol, tomate, etc.
    }

    [HttpGet("cycles/{cycleId:guid}/agronomy")]
    public async Task<ActionResult<AgronomyContext>> Get(Guid cycleId, CancellationToken ct)
    {
        var cycle = await _db.CropCycles
            .Include(c => c.Plot!).ThenInclude(p => p.Farm!)
            .FirstOrDefaultAsync(c => c.Id == cycleId && c.Plot!.Farm!.OrganizationId == OrgId, ct);
        if (cycle is null) return NotFound();

        var start = cycle.ActualStart ?? cycle.PlannedStart;
        var loc = cycle.Plot?.Farm?.Location;
        if (loc is null)
            return Ok(new AgronomyContext(null, null, start, cycle.Crop, BaseTemp(cycle.Crop),
                "La finca no tiene ubicación. Asigna coordenadas a la finca para ver los indicadores agronómicos."));

        return Ok(new AgronomyContext(loc.Y, loc.X, start, cycle.Crop, BaseTemp(cycle.Crop), null));
    }
}
