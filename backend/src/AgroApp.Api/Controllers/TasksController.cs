using AgroApp.Api.Contracts;
using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

[Route("api")]
public class TasksController : ApiControllerBase
{
    private readonly AppDbContext _db;
    public TasksController(AppDbContext db, ICurrentUser me) : base(me) => _db = db;

    private Task<bool> OwnsStage(Guid stageId) =>
        _db.Stages.AnyAsync(s => s.Id == stageId &&
            _db.CropCycles.Any(c => c.Id == s.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId));

    // Tarea accesible si su etapa -> ciclo -> lote -> finca es de la organización.
    private Task<WorkTask?> Find(Guid id) =>
        _db.WorkTasks.FirstOrDefaultAsync(t => t.Id == id &&
            _db.Stages.Any(s => s.Id == t.StageId &&
                _db.CropCycles.Any(c => c.Id == s.CropCycleId && c.Plot!.Farm!.OrganizationId == OrgId)));

    [HttpGet("stages/{stageId:guid}/tasks")]
    public async Task<ActionResult<IEnumerable<TaskResponse>>> List(Guid stageId)
    {
        if (!await OwnsStage(stageId)) return NotFound();
        var tasks = await _db.WorkTasks.Where(t => t.StageId == stageId)
            .OrderBy(t => t.CreatedAt).ToListAsync();
        return Ok(tasks.Select(ToResponse));
    }

    [HttpPost("stages/{stageId:guid}/tasks")]
    public async Task<ActionResult<TaskResponse>> Create(Guid stageId, TaskRequest req)
    {
        if (!await OwnsStage(stageId)) return NotFound();
        var task = new WorkTask
        {
            StageId = stageId,
            Title = req.Title,
            Description = req.Description,
            AssignedToUserId = req.AssignedToUserId,
            DueDate = req.DueDate
        };
        _db.WorkTasks.Add(task);
        await _db.SaveChangesAsync();
        return Ok(ToResponse(task));
    }

    [HttpPut("tasks/{id:guid}")]
    public async Task<ActionResult<TaskResponse>> Update(Guid id, TaskRequest req)
    {
        var task = await Find(id);
        if (task is null) return NotFound();
        task.Title = req.Title;
        task.Description = req.Description;
        task.AssignedToUserId = req.AssignedToUserId;
        task.DueDate = req.DueDate;
        task.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(ToResponse(task));
    }

    [HttpPost("tasks/{id:guid}/status/{status}")]
    public async Task<ActionResult<TaskResponse>> SetStatus(Guid id, WorkTaskStatus status)
    {
        var task = await Find(id);
        if (task is null) return NotFound();
        task.Status = status;
        task.CompletedAt = status == WorkTaskStatus.Done ? DateTimeOffset.UtcNow : null;
        task.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(ToResponse(task));
    }

    [HttpDelete("tasks/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var task = await Find(id);
        if (task is null) return NotFound();
        _db.WorkTasks.Remove(task);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static TaskResponse ToResponse(WorkTask t) => new(
        t.Id, t.StageId, t.Title, t.Description, t.AssignedToUserId, t.Status, t.DueDate, t.CompletedAt);
}
