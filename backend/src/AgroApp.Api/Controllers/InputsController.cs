using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record InputRequest(string Name, InputKind Kind, string Unit, decimal UnitCost, double StockQty, double MinStock);
public record InputResponse(Guid Id, string Name, InputKind Kind, string Unit, decimal UnitCost, double StockQty, double MinStock);
public record RestockRequest(double Quantity);

[Route("api/inputs")]
public class InputsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public InputsController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    [HttpGet]
    public async Task<ActionResult<IEnumerable<InputResponse>>> List()
    {
        var items = await _db.Inputs.Where(i => i.OrganizationId == OrgId)
            .OrderBy(i => i.Name).ToListAsync();
        return Ok(items.Select(ToResponse));
    }

    [HttpPost]
    public async Task<ActionResult<InputResponse>> Create(InputRequest req)
    {
        var input = new Input
        {
            OrganizationId = OrgId,
            Name = req.Name,
            Kind = req.Kind,
            Unit = req.Unit,
            UnitCost = req.UnitCost,
            StockQty = req.StockQty,
            MinStock = req.MinStock
        };
        _db.Inputs.Add(input);
        await _db.SaveChangesAsync();
        return Ok(ToResponse(input));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<InputResponse>> Update(Guid id, InputRequest req)
    {
        var input = await _db.Inputs.FirstOrDefaultAsync(i => i.Id == id && i.OrganizationId == OrgId);
        if (input is null) return NotFound();
        (input.Name, input.Kind, input.Unit, input.UnitCost, input.StockQty, input.MinStock) =
            (req.Name, req.Kind, req.Unit, req.UnitCost, req.StockQty, req.MinStock);
        input.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(ToResponse(input));
    }

    /// <summary>Registra una entrada de inventario (suma existencias).</summary>
    [HttpPost("{id:guid}/restock")]
    public async Task<ActionResult<InputResponse>> Restock(Guid id, RestockRequest req)
    {
        var input = await _db.Inputs.FirstOrDefaultAsync(i => i.Id == id && i.OrganizationId == OrgId);
        if (input is null) return NotFound();
        input.StockQty += req.Quantity;
        input.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(ToResponse(input));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var input = await _db.Inputs.FirstOrDefaultAsync(i => i.Id == id && i.OrganizationId == OrgId);
        if (input is null) return NotFound();
        _db.Inputs.Remove(input);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static InputResponse ToResponse(Input i) => new(i.Id, i.Name, i.Kind, i.Unit, i.UnitCost, i.StockQty, i.MinStock);
}
