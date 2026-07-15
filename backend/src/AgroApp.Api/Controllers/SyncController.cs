using AgroApp.Api.Contracts;
using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

/// <summary>
/// Sincronización offline-first: el cliente empuja su outbox (tareas, observaciones, costos)
/// y recibe el delta del servidor desde el último token. Conflictos: last-write-wins con
/// autoridad del servidor (se aplica el entrante solo si su UpdatedAt es más reciente).
/// </summary>
[Route("api/sync")]
public class SyncController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public SyncController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    [HttpPost]
    public async Task<ActionResult<SyncPullResponse>> Sync(SyncPushRequest req)
    {
        var now = DateTimeOffset.UtcNow;
        await PushAsync(req);
        await _db.SaveChangesAsync();
        var pull = await PullAsync(req.Since, now);
        return Ok(pull);
    }

    private async Task PushAsync(SyncPushRequest req)
    {
        // --- Tareas: la etapa debe pertenecer a la organización ---
        foreach (var dto in req.Tasks ?? [])
        {
            var owns = await _db.Stages.AnyAsync(s => s.Id == dto.StageId &&
                _db.CropCycles.Any(c => c.Id == s.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId));
            if (!owns) continue;

            var entity = await _db.WorkTasks.FindAsync(dto.Id);
            if (entity is null)
            {
                _db.WorkTasks.Add(new WorkTask
                {
                    Id = dto.Id, StageId = dto.StageId, Title = dto.Title, Description = dto.Description,
                    AssignedToUserId = dto.AssignedToUserId, Status = dto.Status, DueDate = dto.DueDate,
                    CompletedAt = dto.CompletedAt, UpdatedAt = dto.UpdatedAt
                });
            }
            else if (dto.UpdatedAt >= entity.UpdatedAt) // last-write-wins
            {
                entity.Title = dto.Title; entity.Description = dto.Description;
                entity.AssignedToUserId = dto.AssignedToUserId; entity.Status = dto.Status;
                entity.DueDate = dto.DueDate; entity.CompletedAt = dto.CompletedAt;
                entity.UpdatedAt = dto.UpdatedAt;
            }
        }

        // --- Observaciones: el ciclo debe pertenecer a la organización ---
        foreach (var dto in req.Observations ?? [])
        {
            var owns = await _db.CropCycles.AnyAsync(c => c.Id == dto.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId);
            if (!owns) continue;

            var entity = await _db.Observations.FindAsync(dto.Id);
            if (entity is null)
            {
                _db.Observations.Add(new Observation
                {
                    Id = dto.Id, CropCycleId = dto.CropCycleId, CreatedByUserId = dto.CreatedByUserId,
                    Location = Geo.ToPoint(dto.Location), Note = dto.Note, PhotoKey = dto.PhotoKey,
                    SyncedAt = DateTimeOffset.UtcNow, UpdatedAt = dto.UpdatedAt
                });
            }
            else if (dto.UpdatedAt >= entity.UpdatedAt)
            {
                entity.Note = dto.Note; entity.Location = Geo.ToPoint(dto.Location);
                entity.PhotoKey = dto.PhotoKey ?? entity.PhotoKey;
                entity.SyncedAt = DateTimeOffset.UtcNow; entity.UpdatedAt = dto.UpdatedAt;
            }
        }

        // --- Costos: el ciclo debe pertenecer a la organización ---
        foreach (var dto in req.Costs ?? [])
        {
            var owns = await _db.CropCycles.AnyAsync(c => c.Id == dto.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId);
            if (!owns) continue;

            var entity = await _db.CostEntries.FindAsync(dto.Id);
            if (entity is null)
            {
                _db.CostEntries.Add(new CostEntry
                {
                    Id = dto.Id, CropCycleId = dto.CropCycleId, Kind = dto.Kind, Description = dto.Description,
                    InputId = dto.InputId, WorkTaskId = dto.WorkTaskId, StageId = dto.StageId, Quantity = dto.Quantity,
                    UnitCost = dto.UnitCost, Total = dto.Total, IncurredAt = dto.IncurredAt, UpdatedAt = dto.UpdatedAt
                });
            }
            else if (dto.UpdatedAt >= entity.UpdatedAt)
            {
                entity.Kind = dto.Kind; entity.Description = dto.Description; entity.Quantity = dto.Quantity;
                entity.InputId = dto.InputId; entity.StageId = dto.StageId;
                entity.UnitCost = dto.UnitCost; entity.Total = dto.Total; entity.UpdatedAt = dto.UpdatedAt;
            }
        }
    }

    private async Task<SyncPullResponse> PullAsync(DateTimeOffset? since, DateTimeOffset now)
    {
        var from = since ?? DateTimeOffset.MinValue;

        var cycles = await _db.CropCycles
            .Where(c => c.Plot!.Farm!.OrganizationId == OrgId && c.UpdatedAt > from)
            .Select(c => new SyncCycleDto(c.Id, c.PlotId, c.Crop, c.Variety, c.Status, c.UpdatedAt))
            .ToListAsync();

        var stages = await _db.Stages
            .Where(s => s.UpdatedAt > from &&
                _db.CropCycles.Any(c => c.Id == s.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId))
            .Select(s => new SyncStageDto(s.Id, s.CropCycleId, s.Kind, s.Status, s.StartedAt, s.CompletedAt, s.Notes, s.UpdatedAt))
            .ToListAsync();

        var tasks = await _db.WorkTasks
            .Where(t => t.UpdatedAt > from &&
                _db.Stages.Any(s => s.Id == t.StageId &&
                    _db.CropCycles.Any(c => c.Id == s.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId)))
            .Select(t => new SyncTaskDto(t.Id, t.StageId, t.Title, t.Description, t.AssignedToUserId,
                t.Status, t.DueDate, t.CompletedAt, t.UpdatedAt))
            .ToListAsync();

        var costs = await _db.CostEntries
            .Where(c => c.UpdatedAt > from &&
                _db.CropCycles.Any(cy => cy.Id == c.CropCycleId && cy.Plot!.Farm!.OrganizationId == OrgId))
            .Select(c => new SyncCostDto(c.Id, c.CropCycleId, c.Kind, c.Description, c.InputId, c.WorkTaskId,
                c.StageId, c.Quantity, c.UnitCost, c.Total, c.IncurredAt, c.UpdatedAt))
            .ToListAsync();

        // Observaciones: la geometría no viaja en el pull (el cliente ya la tiene o la reconstruye del detalle).
        var obs = await _db.Observations
            .Where(o => o.UpdatedAt > from &&
                _db.CropCycles.Any(c => c.Id == o.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId))
            .Select(o => new SyncObservationDto(o.Id, o.CropCycleId, o.CreatedByUserId, null, o.Note, o.PhotoKey, o.UpdatedAt))
            .ToListAsync();

        return new SyncPullResponse(now, cycles, stages, tasks, costs, obs);
    }
}
