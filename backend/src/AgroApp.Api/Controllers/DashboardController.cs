using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record DashboardFarm(Guid Id, string Name, double? Lat, double? Lng, double AreaHa);
public record DashboardStage(int Kind, int Status);
public record DashboardCycle(Guid Id, Guid PlotId, string Crop, string? Variety,
    IEnumerable<DashboardStage> Stages, decimal TotalCost);
public record DashboardTask(Guid Id, string Title, DateOnly? DueDate, string Crop, bool Overdue);
public record CostSlice(int Kind, decimal Total);
public record DashboardAlert(string Level, string Message);  // danger | warning | info
public record DashboardResponse(
    int Farms, int Plots, int ActiveCycles, int PlannedCycles, int ClosedCycles,
    int PendingTasks, int OverdueTasks, decimal TotalCost, IEnumerable<DashboardFarm> FarmsList,
    IEnumerable<DashboardCycle> ActiveCyclesList, IEnumerable<DashboardTask> UpcomingTasks,
    IEnumerable<CostSlice> CostByKind, IEnumerable<DashboardAlert> Alerts);

/// <summary>Métricas agregadas de la organización para el panel de inicio.</summary>
[Route("api/dashboard")]
public class DashboardController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly IAgronomyService _agronomy;
    public DashboardController(AppDbContext db, IAgronomyService agronomy, ICurrentUser me) : base(me)
    {
        _db = db;
        _agronomy = agronomy;
    }

    [HttpGet]
    public async Task<ActionResult<DashboardResponse>> Get()
    {
        var farms = _db.Farms.Where(f => f.OrganizationId == OrgId);
        var cycles = _db.CropCycles.Where(c => c.Plot!.Farm!.OrganizationId == OrgId);

        var farmsList = await farms
            .Select(f => new DashboardFarm(f.Id, f.Name,
                f.Location != null ? f.Location.Y : (double?)null,
                f.Location != null ? f.Location.X : (double?)null,
                f.AreaHa))
            .ToListAsync();

        var pendingTasks = await _db.WorkTasks
            .CountAsync(t => t.Status != WorkTaskStatus.Done &&
                _db.Stages.Any(s => s.Id == t.StageId &&
                    _db.CropCycles.Any(c => c.Id == s.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId)));

        var totalCost = await _db.CostEntries
            .Where(c => _db.CropCycles.Any(cy => cy.Id == c.CropCycleId && cy.Plot!.Farm!.OrganizationId == OrgId))
            .SumAsync(c => (decimal?)c.Total) ?? 0m;

        var activeCyclesList = await cycles
            .Where(c => c.Status == CropCycleStatus.Active)
            .Select(c => new DashboardCycle(c.Id, c.PlotId, c.Crop, c.Variety,
                c.Stages.OrderBy(s => s.Kind).Select(s => new DashboardStage((int)s.Kind, (int)s.Status)),
                _db.CostEntries.Where(ce => ce.CropCycleId == c.Id).Sum(ce => (decimal?)ce.Total) ?? 0m))
            .ToListAsync();

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        // Tareas próximas / vencidas (no completadas, con fecha) — ordenadas por fecha.
        var pendingWithDate = await (
            from t in _db.WorkTasks
            join s in _db.Stages on t.StageId equals s.Id
            join c in _db.CropCycles on s.CropCycleId equals c.Id
            where c.Plot!.Farm!.OrganizationId == OrgId && t.Status != WorkTaskStatus.Done && t.DueDate != null
            orderby t.DueDate
            select new { t.Id, t.Title, t.DueDate, c.Crop }).ToListAsync();
        var upcoming = pendingWithDate.Take(8)
            .Select(x => new DashboardTask(x.Id, x.Title, x.DueDate, x.Crop, x.DueDate < today))
            .ToList();
        var overdueTasks = pendingWithDate.Count(x => x.DueDate < today);

        // Costo por tipo.
        var costByKind = await _db.CostEntries
            .Where(c => _db.CropCycles.Any(cy => cy.Id == c.CropCycleId && cy.Plot!.Farm!.OrganizationId == OrgId))
            .GroupBy(c => c.Kind)
            .Select(g => new CostSlice((int)g.Key, g.Sum(x => x.Total)))
            .ToListAsync();

        // Alertas: fitosanitarias (último monitoreo por ciclo activo) + tareas vencidas.
        var alerts = new List<DashboardAlert>();
        if (overdueTasks > 0)
            alerts.Add(new DashboardAlert("danger", $"{overdueTasks} tarea(s) vencida(s) sin completar."));

        // Stock bajo: insumos con existencias <= umbral (umbral > 0).
        var lowStock = await _db.Inputs
            .Where(i => i.OrganizationId == OrgId && i.MinStock > 0 && i.StockQty <= i.MinStock)
            .ToListAsync();
        foreach (var i in lowStock)
            alerts.Add(new DashboardAlert("warning", $"Stock bajo: {i.Name} ({i.StockQty:0.##} {i.Unit})."));

        var phen = await _db.PhenologyRecords
            .Where(p => _db.CropCycles.Any(c => c.Id == p.CropCycleId &&
                c.Status == CropCycleStatus.Active && c.Plot!.Farm!.OrganizationId == OrgId))
            .ToListAsync();
        foreach (var g in phen.GroupBy(p => p.CropCycleId))
        {
            var last = g.OrderByDescending(p => p.RecordedAt).First();
            var crop = activeCyclesList.FirstOrDefault(c => c.Id == g.Key)?.Crop ?? "Cultivo";
            if ((last.PestIncidencePct ?? 0) >= 10)
                alerts.Add(new DashboardAlert("warning", $"{crop}: incidencia de plagas {last.PestIncidencePct:0}% (último monitoreo)."));
            if ((last.DiseaseIncidencePct ?? 0) >= 10)
                alerts.Add(new DashboardAlert("warning", $"{crop}: incidencia de enfermedad {last.DiseaseIncidencePct:0}% (último monitoreo)."));
        }

        // Agronomía (Open-Meteo): déficit hídrico y riesgo de enfermedad por ciclo activo
        // con finca ubicada. Best-effort: un fallo del servicio nunca rompe el dashboard.
        var agroCycles = await cycles
            .Where(c => c.Status == CropCycleStatus.Active && c.Plot!.Farm!.Location != null)
            .Select(c => new
            {
                c.Crop,
                Lat = c.Plot!.Farm!.Location!.Y,
                Lng = c.Plot!.Farm!.Location!.X,
                Start = c.ActualStart ?? c.PlannedStart
            })
            .ToListAsync();
        foreach (var c in agroCycles)
        {
            try
            {
                var a = await _agronomy.GetAsync(c.Lat, c.Lng, c.Start, c.Crop);
                if (a.Water?.IrrigationSuggested == true)
                    alerts.Add(new DashboardAlert("warning",
                        $"Déficit hídrico: {c.Crop} necesita ~{a.Water.SuggestedMm:0} mm de riego (7 días)."));
                if (a.Disease is { Level: "high" or "medium" } d)
                    alerts.Add(new DashboardAlert(d.Level == "high" ? "danger" : "warning",
                        $"Riesgo de enfermedad {(d.Level == "high" ? "alto" : "medio")} en {c.Crop} (humedad/temperatura favorables a hongos)."));
            }
            catch { /* Open-Meteo no disponible: omitir alertas agronómicas */ }
        }

        return Ok(new DashboardResponse(
            Farms: farmsList.Count,
            Plots: await _db.Plots.CountAsync(p => p.Farm!.OrganizationId == OrgId),
            ActiveCycles: await cycles.CountAsync(c => c.Status == CropCycleStatus.Active),
            PlannedCycles: await cycles.CountAsync(c => c.Status == CropCycleStatus.Planned),
            ClosedCycles: await cycles.CountAsync(c => c.Status == CropCycleStatus.Closed),
            PendingTasks: pendingTasks,
            OverdueTasks: overdueTasks,
            TotalCost: totalCost,
            FarmsList: farmsList,
            ActiveCyclesList: activeCyclesList,
            UpcomingTasks: upcoming,
            CostByKind: costByKind,
            Alerts: alerts));
    }
}
