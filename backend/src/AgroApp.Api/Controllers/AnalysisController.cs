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

public record NutrientRec(string Nutrient, double? Value, string Unit, string Status, string Recommendation);
public record FertilizationPlan(bool HasAnalysis, DateOnly? SampledAt, IEnumerable<NutrientRec> Items, string Note);

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

    /// <summary>Plan de fertilización orientativo a partir del último análisis de suelo del lote.</summary>
    [HttpGet("plots/{plotId:guid}/fertilization")]
    public async Task<ActionResult<FertilizationPlan>> Fertilization(Guid plotId)
    {
        if (!await OwnsPlot(plotId)) return NotFound();
        var a = await _db.Analyses.Where(x => x.PlotId == plotId && x.Kind == AnalysisKind.Soil)
            .OrderByDescending(x => x.SampledAt).FirstOrDefaultAsync();
        if (a is null)
            return Ok(new FertilizationPlan(false, null, Array.Empty<NutrientRec>(),
                "Aún no hay análisis de suelo para este lote. Registra uno para obtener recomendaciones."));

        var items = new List<NutrientRec>();

        if (a.Ph is double ph)
            items.Add(new NutrientRec("pH", ph, "",
                ph < 5.5 ? "low" : ph > 7.2 ? "high" : "ok",
                ph < 5.5 ? "Suelo ácido: aplicar cal agrícola (encalado) para subir el pH y liberar nutrientes."
                : ph > 7.2 ? "Suelo alcalino: incorporar materia orgánica o azufre para bajar el pH."
                : "pH en rango óptimo; mantener."));

        if (a.OrganicMatter is double om)
            items.Add(new NutrientRec("Materia orgánica", om, "%",
                om < 2 ? "low" : om > 5 ? "high" : "ok",
                om < 2 ? "Baja: incorporar compost, estiércol o abonos verdes para mejorar estructura y retención."
                : om > 5 ? "Alta: buen nivel; cuidar la mineralización."
                : "Adecuada; mantener aportes orgánicos."));

        if (a.N is double n)
            items.Add(new NutrientRec("Nitrógeno (N)", n, "%",
                n < 0.15 ? "low" : n > 0.3 ? "high" : "ok",
                n < 0.15 ? "Bajo: programar fertilización nitrogenada (urea/sulfato de amonio) fraccionada."
                : n > 0.3 ? "Alto: evitar más N para no favorecer plagas ni lixiviación."
                : "Adecuado; reponer según extracción del cultivo."));

        if (a.P is double p)
            items.Add(new NutrientRec("Fósforo (P)", p, "ppm",
                p < 15 ? "low" : p > 40 ? "high" : "ok",
                p < 15 ? "Bajo: aplicar fuente fosfatada (DAP/superfosfato) al establecimiento."
                : p > 40 ? "Alto: reducir aportes de P."
                : "Adecuado; mantenimiento."));

        if (a.K is double k)
            items.Add(new NutrientRec("Potasio (K)", k, "ppm",
                k < 120 ? "low" : k > 250 ? "high" : "ok",
                k < 120 ? "Bajo: aplicar fuente potásica (KCl/sulfato de potasio), clave en llenado de grano/fruto."
                : k > 250 ? "Alto: reducir aportes de K."
                : "Adecuado; mantenimiento."));

        return Ok(new FertilizationPlan(true, a.SampledAt, items,
            "Rangos orientativos. Ajusta las dosis con tu laboratorio y el requerimiento específico del cultivo."));
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
