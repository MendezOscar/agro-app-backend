using AgroApp.Domain;

namespace AgroApp.Api.Contracts;

public record CreateCycleRequest(
    Guid PlotId, string Crop, string? Variety, DateOnly? PlannedStart, DateOnly? PlannedEnd);

public record CycleResponse(
    Guid Id, Guid PlotId, string Crop, string? Variety, CropCycleStatus Status,
    DateOnly? PlannedStart, DateOnly? ActualStart, DateOnly? PlannedEnd, DateOnly? ActualEnd,
    double? YieldKg, IEnumerable<StageResponse>? Stages);

public record StageResponse(
    Guid Id, StageKind Kind, StageStatus Status,
    DateTimeOffset? StartedAt, DateTimeOffset? CompletedAt, string? Notes);

public record AdvanceStageRequest(StageStatus Status, string? Notes);

public record CloseCycleRequest(
    double YieldKg, string? Quality, double PostHarvestLossKg, decimal RevenueEst, string? Notes);

public record TaskRequest(string Title, string? Description, Guid? AssignedToUserId, DateOnly? DueDate);
public record TaskResponse(
    Guid Id, Guid StageId, string Title, string? Description, Guid? AssignedToUserId,
    WorkTaskStatus Status, DateOnly? DueDate, DateTimeOffset? CompletedAt);

public record CostRequest(
    CostKind Kind, string? Description, Guid? InputId, Guid? WorkTaskId, decimal Quantity, decimal UnitCost);
public record CostResponse(
    Guid Id, CostKind Kind, string? Description, Guid? InputId, Guid? WorkTaskId,
    decimal Quantity, decimal UnitCost, decimal Total, DateTimeOffset IncurredAt);
