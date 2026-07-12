using AgroApp.Api.Contracts;
using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

[ApiController]
[Authorize]
[Route("api")]
public class PlotsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly ISpatialService _spatial;

    public PlotsController(AppDbContext db, ICurrentUser me, ISpatialService spatial)
    {
        _db = db;
        _me = me;
        _spatial = spatial;
    }

    private Guid OrgId => _me.OrganizationId ?? throw new UnauthorizedAccessException();

    [HttpGet("farms/{farmId:guid}/plots")]
    public async Task<ActionResult<IEnumerable<PlotResponse>>> List(Guid farmId)
    {
        if (!await OwnsFarm(farmId)) return NotFound();
        var plots = await _db.Plots.Where(p => p.FarmId == farmId).OrderBy(p => p.Name).ToListAsync();
        return Ok(plots.Select(ToResponse));
    }

    [HttpPost("farms/{farmId:guid}/plots")]
    public async Task<ActionResult<PlotResponse>> Create(Guid farmId, PlotRequest req)
    {
        if (!await OwnsFarm(farmId)) return NotFound();

        var plot = new Plot
        {
            FarmId = farmId,
            Name = req.Name,
            SoilType = req.SoilType,
            Boundary = Geo.ToPolygon(req.Boundary)
        };
        if (plot.Boundary is not null)
            plot.AreaHa = await _spatial.PolygonAreaHectaresAsync(plot.Boundary);

        _db.Plots.Add(plot);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = plot.Id }, ToResponse(plot));
    }

    [HttpGet("plots/{id:guid}")]
    public async Task<ActionResult<PlotResponse>> Get(Guid id)
    {
        var plot = await Find(id);
        return plot is null ? NotFound() : Ok(ToResponse(plot));
    }

    [HttpPut("plots/{id:guid}")]
    public async Task<ActionResult<PlotResponse>> Update(Guid id, PlotRequest req)
    {
        var plot = await Find(id);
        if (plot is null) return NotFound();

        plot.Name = req.Name;
        plot.SoilType = req.SoilType;
        plot.Boundary = Geo.ToPolygon(req.Boundary);
        plot.AreaHa = plot.Boundary is null ? 0 : await _spatial.PolygonAreaHectaresAsync(plot.Boundary);
        plot.UpdatedAt = DateTimeOffset.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(ToResponse(plot));
    }

    [HttpDelete("plots/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var plot = await Find(id);
        if (plot is null) return NotFound();
        _db.Plots.Remove(plot);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Task<bool> OwnsFarm(Guid farmId) =>
        _db.Farms.AnyAsync(f => f.Id == farmId && f.OrganizationId == OrgId);

    // Un plot es accesible si su finca pertenece a la organización del usuario.
    private Task<Plot?> Find(Guid id) =>
        _db.Plots.Include(p => p.Farm)
            .FirstOrDefaultAsync(p => p.Id == id && p.Farm!.OrganizationId == OrgId);

    private static PlotResponse ToResponse(Plot p) => new(
        p.Id, p.FarmId, p.Name, Geo.FromPolygon(p.Boundary), p.AreaHa, p.SoilType);
}
