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
[Route("api/farms")]
public class FarmsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly ISpatialService _spatial;

    public FarmsController(AppDbContext db, ICurrentUser me, ISpatialService spatial)
    {
        _db = db;
        _me = me;
        _spatial = spatial;
    }

    private Guid OrgId => _me.OrganizationId ?? throw new UnauthorizedAccessException();

    [HttpGet]
    public async Task<ActionResult<IEnumerable<FarmResponse>>> List()
    {
        var farms = await _db.Farms.Where(f => f.OrganizationId == OrgId)
            .OrderBy(f => f.Name).ToListAsync();
        return Ok(farms.Select(ToResponse));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<FarmResponse>> Get(Guid id)
    {
        var farm = await Find(id);
        return farm is null ? NotFound() : Ok(ToResponse(farm));
    }

    [HttpPost]
    public async Task<ActionResult<FarmResponse>> Create(FarmRequest req)
    {
        var farm = new Farm
        {
            OrganizationId = OrgId,
            Name = req.Name,
            Location = Geo.ToPoint(req.Location),
            Boundary = Geo.ToPolygon(req.Boundary)
        };
        if (farm.Boundary is not null)
            farm.AreaHa = await _spatial.PolygonAreaHectaresAsync(farm.Boundary);

        _db.Farms.Add(farm);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = farm.Id }, ToResponse(farm));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<FarmResponse>> Update(Guid id, FarmRequest req)
    {
        var farm = await Find(id);
        if (farm is null) return NotFound();

        farm.Name = req.Name;
        farm.Location = Geo.ToPoint(req.Location);
        farm.Boundary = Geo.ToPolygon(req.Boundary);
        farm.AreaHa = farm.Boundary is null ? 0 : await _spatial.PolygonAreaHectaresAsync(farm.Boundary);
        farm.UpdatedAt = DateTimeOffset.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(ToResponse(farm));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var farm = await Find(id);
        if (farm is null) return NotFound();
        _db.Farms.Remove(farm);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Task<Farm?> Find(Guid id) =>
        _db.Farms.FirstOrDefaultAsync(f => f.Id == id && f.OrganizationId == OrgId);

    private static FarmResponse ToResponse(Farm f) => new(
        f.Id, f.Name, Geo.FromPoint(f.Location), Geo.FromPolygon(f.Boundary), f.AreaHa, f.CreatedAt);
}
