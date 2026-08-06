using AgroApp.Application.Common;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

/// <summary>Contexto para calcular indicadores agronómicos en el cliente (que llama a Open-Meteo
/// desde su propia IP, evitando el límite por IP compartida de Render).</summary>
public record AgronomyContext(
    double? Lat, double? Lng, DateOnly? CycleStart, string Crop, double BaseTempC, string? Message,
    double AreaHa, double Kc, string KcStage);

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

    // Coeficiente de cultivo Kc [inicial, media, final] por cultivo (FAO-56, orientativo).
    private static (double ini, double mid, double end, bool perennial) KcTable(string crop)
    {
        var c = (crop ?? "").ToLowerInvariant();
        if (c.Contains("café") || c.Contains("cafe") || c.Contains("coffee")) return (0.9, 0.95, 0.95, true);
        if (c.Contains("maíz") || c.Contains("maiz") || c.Contains("corn")) return (0.4, 1.2, 0.6, false);
        if (c.Contains("arroz") || c.Contains("rice")) return (1.05, 1.2, 0.9, false);
        if (c.Contains("papa") || c.Contains("patata") || c.Contains("potato")) return (0.5, 1.15, 0.75, false);
        if (c.Contains("trigo") || c.Contains("wheat")) return (0.4, 1.15, 0.4, false);
        if (c.Contains("frijol") || c.Contains("fríjol") || c.Contains("bean")) return (0.4, 1.15, 0.35, false);
        if (c.Contains("tomate") || c.Contains("tomato")) return (0.6, 1.15, 0.8, false);
        return (0.5, 1.0, 0.7, false);
    }

    // Elige Kc según los días transcurridos desde el inicio del ciclo.
    private static (double kc, string stage) KcForCycle(string crop, DateOnly? start)
    {
        var t = KcTable(crop);
        if (t.perennial) return (t.mid, "Perenne");
        if (start is null) return (t.mid, "Media");
        var days = DateOnly.FromDateTime(DateTime.UtcNow).DayNumber - start.Value.DayNumber;
        if (days < 35) return (t.ini, "Inicial");
        if (days <= 100) return (t.mid, "Media");
        return (t.end, "Final");
    }

    [HttpGet("cycles/{cycleId:guid}/agronomy")]
    public async Task<ActionResult<AgronomyContext>> Get(Guid cycleId, CancellationToken ct)
    {
        var cycle = await _db.CropCycles
            .Include(c => c.Plot!).ThenInclude(p => p.Farm!)
            .FirstOrDefaultAsync(c => c.Id == cycleId && c.Plot!.Farm!.OrganizationId == OrgId, ct);
        if (cycle is null) return NotFound();

        var start = cycle.ActualStart ?? cycle.PlannedStart;
        var area = cycle.Plot?.AreaHa ?? 0;
        var (kc, kcStage) = KcForCycle(cycle.Crop, start);
        var loc = cycle.Plot?.Farm?.Location;
        if (loc is null)
            return Ok(new AgronomyContext(null, null, start, cycle.Crop, BaseTemp(cycle.Crop),
                "La finca no tiene ubicación. Asigna coordenadas a la finca para ver los indicadores agronómicos.",
                area, kc, kcStage));

        return Ok(new AgronomyContext(loc.Y, loc.X, start, cycle.Crop, BaseTemp(cycle.Crop), null, area, kc, kcStage));
    }
}
