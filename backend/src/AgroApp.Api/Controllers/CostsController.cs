using AgroApp.Api.Contracts;
using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record CostSummaryResponse(decimal Total, IEnumerable<CostByKind> ByKind);
public record CostByKind(CostKind Kind, decimal Total);

[Route("api")]
public class CostsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public CostsController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    private Task<bool> OwnsCycle(Guid cycleId) =>
        _db.CropCycles.AnyAsync(c => c.Id == cycleId && c.Plot!.Farm!.OrganizationId == OrgId);

    [HttpGet("cycles/{cycleId:guid}/costs")]
    public async Task<ActionResult<IEnumerable<CostResponse>>> List(Guid cycleId)
    {
        if (!await OwnsCycle(cycleId)) return NotFound();
        var costs = await _db.CostEntries.Where(c => c.CropCycleId == cycleId)
            .OrderByDescending(c => c.IncurredAt).ToListAsync();
        return Ok(costs.Select(ToResponse));
    }

    [HttpPost("cycles/{cycleId:guid}/costs")]
    public async Task<ActionResult<CostResponse>> Create(Guid cycleId, CostRequest req)
    {
        if (!await OwnsCycle(cycleId)) return NotFound();

        // Si se indica un insumo y no viene costo unitario, se toma del catálogo.
        var unitCost = req.UnitCost;
        if (req.InputId is { } inputId && unitCost == 0)
        {
            var input = await _db.Inputs.FirstOrDefaultAsync(i => i.Id == inputId && i.OrganizationId == OrgId);
            if (input is not null) unitCost = input.UnitCost;
        }

        var cost = new CostEntry
        {
            CropCycleId = cycleId,
            Kind = req.Kind,
            Description = req.Description,
            InputId = req.InputId,
            WorkTaskId = req.WorkTaskId,
            Quantity = req.Quantity,
            UnitCost = unitCost,
            Total = req.Quantity * unitCost
        };
        _db.CostEntries.Add(cost);
        await _db.SaveChangesAsync();
        return Ok(ToResponse(cost));
    }

    [HttpGet("cycles/{cycleId:guid}/costs/summary")]
    public async Task<ActionResult<CostSummaryResponse>> Summary(Guid cycleId)
    {
        if (!await OwnsCycle(cycleId)) return NotFound();
        var byKind = await _db.CostEntries.Where(c => c.CropCycleId == cycleId)
            .GroupBy(c => c.Kind)
            .Select(g => new CostByKind(g.Key, g.Sum(x => x.Total)))
            .ToListAsync();
        return Ok(new CostSummaryResponse(byKind.Sum(k => k.Total), byKind));
    }

    [HttpDelete("costs/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var cost = await _db.CostEntries.FirstOrDefaultAsync(c => c.Id == id &&
            _db.CropCycles.Any(cy => cy.Id == c.CropCycleId && cy.Plot!.Farm!.OrganizationId == OrgId));
        if (cost is null) return NotFound();
        _db.CostEntries.Remove(cost);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static CostResponse ToResponse(CostEntry c) => new(
        c.Id, c.Kind, c.Description, c.InputId, c.WorkTaskId, c.Quantity, c.UnitCost, c.Total, c.IncurredAt);
}
