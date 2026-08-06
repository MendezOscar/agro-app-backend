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
public record FertilizerDose(
    string Nutrient, double DoseKgHa, string Product, double ProductKgHa,
    double TotalKg, double Bags, decimal EstCost);
public record FertilizerRecipe(
    string Crop, double AreaHa, double TargetYieldTonHa, decimal TotalCost,
    IEnumerable<FertilizerDose> Doses, string Note);
public record FertilizationPlan(
    bool HasAnalysis, DateOnly? SampledAt, IEnumerable<NutrientRec> Items, string Note,
    FertilizerRecipe? Recipe);

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
                "Aún no hay análisis de suelo para este lote. Registra uno para obtener recomendaciones.", null));

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

        var plot = await _db.Plots.Include(p => p.CropCycles)
            .FirstOrDefaultAsync(p => p.Id == plotId);
        var crop = plot?.CropCycles.OrderByDescending(c => c.CreatedAt).Select(c => c.Crop).FirstOrDefault() ?? "";
        var recipe = BuildRecipe(crop, plot?.AreaHa ?? 0, a);

        return Ok(new FertilizationPlan(true, a.SampledAt, items,
            "Rangos orientativos. Ajusta las dosis con tu laboratorio y el requerimiento específico del cultivo.",
            recipe));
    }

    // Extracción de nutrientes (kg de N, P₂O₅, K₂O por tonelada de cosecha) y rendimiento
    // meta orientativo (t/ha) por cultivo. Base para dimensionar la dosis.
    private static (double n, double p, double k, double targetTon) ExtractionOf(string crop)
    {
        var c = (crop ?? "").ToLowerInvariant();
        if (c.Contains("café") || c.Contains("cafe") || c.Contains("coffee")) return (35, 6, 45, 1.5);
        if (c.Contains("maíz") || c.Contains("maiz") || c.Contains("corn")) return (22, 8, 20, 6);
        if (c.Contains("arroz") || c.Contains("rice")) return (18, 9, 22, 5);
        if (c.Contains("papa") || c.Contains("patata") || c.Contains("potato")) return (4, 1.5, 6, 25);
        if (c.Contains("trigo") || c.Contains("wheat")) return (25, 11, 18, 4);
        if (c.Contains("frijol") || c.Contains("fríjol") || c.Contains("bean")) return (40, 8, 25, 1.5);
        if (c.Contains("tomate") || c.Contains("tomato")) return (3, 0.7, 5, 40);
        return (20, 8, 20, 5);
    }

    // Traduce el análisis de suelo + extracción del cultivo en una receta con dosis (kg/ha),
    // producto comercial, cantidad para el lote y costo orientativo. No es prescripción de laboratorio.
    private static FertilizerRecipe? BuildRecipe(string crop, double areaHa, Analysis a)
    {
        if (areaHa <= 0) return null;
        var (exN, exP, exK, target) = ExtractionOf(crop);

        // Multiplicador según nivel en suelo: bajo sube la dosis, alto la reduce.
        double mult(double? val, double low, double high) =>
            val is null ? 1.0 : (val < low ? 1.2 : val > high ? 0.5 : 1.0);
        var reqN = exN * target * mult(a.N, 0.15, 0.3);
        var reqP = exP * target * mult(a.P, 15, 40);
        var reqK = exK * target * mult(a.K, 120, 250);

        const double bag = 45.36; // 1 quintal
        const decimal pUrea = 950m, pDap = 1250m, pKcl = 1150m; // L/quintal, orientativo

        var doses = new List<FertilizerDose>();
        decimal total = 0;
        FertilizerDose make(string nutr, double doseKgHa, string product, double productKgHa, decimal pricePerBag)
        {
            var totalKg = productKgHa * areaHa;
            var bags = totalKg / bag;
            var cost = Math.Round((decimal)bags * pricePerBag, 0);
            total += cost;
            return new FertilizerDose(nutr, Math.Round(doseKgHa), product, Math.Round(productKgHa),
                Math.Round(totalKg), Math.Round(bags, 1), cost);
        }

        // P₂O₅ vía DAP (18-46-0), que además aporta N (18%).
        var dapKgHa = reqP > 0 ? reqP / 0.46 : 0;
        if (dapKgHa > 0) doses.Add(make("Fósforo (P₂O₅)", reqP, "DAP (18-46-0)", dapKgHa, pDap));
        // N restante vía Urea (46-0-0), descontando el N que ya aporta el DAP.
        var nFromDap = dapKgHa * 0.18;
        var ureaKgHa = Math.Max(0, reqN - nFromDap) / 0.46;
        if (ureaKgHa > 0) doses.Add(make("Nitrógeno (N)", reqN, "Urea (46-0-0)", ureaKgHa, pUrea));
        // K₂O vía KCl (0-0-60).
        var kclKgHa = reqK > 0 ? reqK / 0.60 : 0;
        if (kclKgHa > 0) doses.Add(make("Potasio (K₂O)", reqK, "KCl (0-0-60)", kclKgHa, pKcl));

        return new FertilizerRecipe(
            string.IsNullOrWhiteSpace(crop) ? "Cultivo" : crop, areaHa, target, total, doses,
            "Dosis orientativa para el rendimiento meta, ajustada por el nivel del suelo. Precios y cantidades aproximados: valida con tu laboratorio y proveedor.");
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
