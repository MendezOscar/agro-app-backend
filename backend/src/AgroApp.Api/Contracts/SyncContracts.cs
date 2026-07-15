using AgroApp.Domain;

namespace AgroApp.Api.Contracts;

// DTOs de sincronización: llevan UpdatedAt para resolución last-write-wins.
public record SyncTaskDto(
    Guid Id, Guid StageId, string Title, string? Description, Guid? AssignedToUserId,
    WorkTaskStatus Status, DateOnly? DueDate, DateTimeOffset? CompletedAt, DateTimeOffset UpdatedAt);

public record SyncObservationDto(
    Guid Id, Guid CropCycleId, Guid CreatedByUserId, double[]? Location, string? Note,
    string? PhotoKey, DateTimeOffset UpdatedAt);

public record SyncCostDto(
    Guid Id, Guid CropCycleId, CostKind Kind, string? Description, Guid? InputId, Guid? WorkTaskId,
    Guid? StageId, decimal Quantity, decimal UnitCost, decimal Total, DateTimeOffset IncurredAt, DateTimeOffset UpdatedAt);

public record SyncStageDto(
    Guid Id, Guid CropCycleId, StageKind Kind, StageStatus Status,
    DateTimeOffset? StartedAt, DateTimeOffset? CompletedAt, string? Notes, DateTimeOffset UpdatedAt);

public record SyncCycleDto(
    Guid Id, Guid PlotId, string Crop, string? Variety, CropCycleStatus Status, DateTimeOffset UpdatedAt);

/// <summary>Outbox del cliente: cambios locales a empujar.</summary>
public record SyncPushRequest(
    DateTimeOffset? Since,
    List<SyncTaskDto>? Tasks,
    List<SyncObservationDto>? Observations,
    List<SyncCostDto>? Costs);

/// <summary>Delta del servidor: entidades cambiadas desde 'Since'.</summary>
public record SyncPullResponse(
    DateTimeOffset ServerTime,
    List<SyncCycleDto> Cycles,
    List<SyncStageDto> Stages,
    List<SyncTaskDto> Tasks,
    List<SyncCostDto> Costs,
    List<SyncObservationDto> Observations);
