using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record DashboardFarm(Guid Id, string Name, double? Lat, double? Lng, double AreaHa);
public record DashboardStage(int Kind, int Status);
public record DashboardCycle(Guid Id, Guid PlotId, string Crop, string? Variety, IEnumerable<DashboardStage> Stages);
public record DashboardResponse(
    int Farms, int Plots, int ActiveCycles, int PlannedCycles, int ClosedCycles,
    int PendingTasks, decimal TotalCost, IEnumerable<DashboardFarm> FarmsList,
    IEnumerable<DashboardCycle> ActiveCyclesList);

/// <summary>Métricas agregadas de la organización para el panel de inicio.</summary>
[Route("api/dashboard")]
public class DashboardController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public DashboardController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

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
                c.Stages.OrderBy(s => s.Kind).Select(s => new DashboardStage((int)s.Kind, (int)s.Status))))
            .ToListAsync();

        return Ok(new DashboardResponse(
            Farms: farmsList.Count,
            Plots: await _db.Plots.CountAsync(p => p.Farm!.OrganizationId == OrgId),
            ActiveCycles: await cycles.CountAsync(c => c.Status == CropCycleStatus.Active),
            PlannedCycles: await cycles.CountAsync(c => c.Status == CropCycleStatus.Planned),
            ClosedCycles: await cycles.CountAsync(c => c.Status == CropCycleStatus.Closed),
            PendingTasks: pendingTasks,
            TotalCost: totalCost,
            FarmsList: farmsList,
            ActiveCyclesList: activeCyclesList));
    }
}
