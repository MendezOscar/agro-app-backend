using NetTopologySuite.Geometries;

namespace AgroApp.Domain;

/// <summary>Base con Id (UUID generado en cliente para permitir creación offline) y marca de tiempo de actualización para sync.</summary>
public abstract class Entity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

/// <summary>Tenant raíz. Todo dato de negocio se aísla por OrganizationId.</summary>
public class Organization : Entity
{
    public string Name { get; set; } = string.Empty;

    public ICollection<Farm> Farms { get; set; } = new List<Farm>();
    public ICollection<Input> Inputs { get; set; } = new List<Input>();
}

public class Farm : Entity
{
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = string.Empty;
    public Point? Location { get; set; }
    public Polygon? Boundary { get; set; }
    public double AreaHa { get; set; }

    public ICollection<Plot> Plots { get; set; } = new List<Plot>();
}

public class Plot : Entity
{
    public Guid FarmId { get; set; }
    public Farm? Farm { get; set; }
    public string Name { get; set; } = string.Empty;
    public Polygon? Boundary { get; set; }
    public double AreaHa { get; set; }
    public string? SoilType { get; set; }

    public ICollection<CropCycle> CropCycles { get; set; } = new List<CropCycle>();
    public ICollection<Analysis> Analyses { get; set; } = new List<Analysis>();
}

public class CropCycle : Entity
{
    public Guid PlotId { get; set; }
    public Plot? Plot { get; set; }
    public string Crop { get; set; } = string.Empty;
    public string? Variety { get; set; }
    public CropCycleStatus Status { get; set; } = CropCycleStatus.Planned;
    public DateOnly? PlannedStart { get; set; }
    public DateOnly? ActualStart { get; set; }
    public DateOnly? PlannedEnd { get; set; }
    public DateOnly? ActualEnd { get; set; }
    public double? YieldKg { get; set; }

    public ICollection<Stage> Stages { get; set; } = new List<Stage>();
    public ICollection<CostEntry> Costs { get; set; } = new List<CostEntry>();
    public ICollection<Observation> Observations { get; set; } = new List<Observation>();
    public HarvestResult? HarvestResult { get; set; }
}

public class Stage : Entity
{
    public Guid CropCycleId { get; set; }
    public StageKind Kind { get; set; }
    public StageStatus Status { get; set; } = StageStatus.Pending;
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public string? Notes { get; set; }

    public ICollection<WorkTask> Tasks { get; set; } = new List<WorkTask>();
}

public class WorkTask : Entity
{
    public Guid StageId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Guid? AssignedToUserId { get; set; }
    public WorkTaskStatus Status { get; set; } = WorkTaskStatus.Todo;
    public DateOnly? DueDate { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
}

public class Input : Entity
{
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = string.Empty;
    public InputKind Kind { get; set; }
    public string Unit { get; set; } = string.Empty;
    public decimal UnitCost { get; set; }
}

public class CostEntry : Entity
{
    public Guid CropCycleId { get; set; }
    public Guid? WorkTaskId { get; set; }
    public Guid? InputId { get; set; }
    public CostKind Kind { get; set; }
    public string? Description { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitCost { get; set; }
    public decimal Total { get; set; }
    public DateTimeOffset IncurredAt { get; set; } = DateTimeOffset.UtcNow;
}

public class Analysis : Entity
{
    public Guid PlotId { get; set; }
    public AnalysisKind Kind { get; set; }
    public double? Ph { get; set; }
    public double? N { get; set; }
    public double? P { get; set; }
    public double? K { get; set; }
    public double? OrganicMatter { get; set; }
    public string? Texture { get; set; }
    public DateOnly? SampledAt { get; set; }
}

public class Observation : Entity
{
    public Guid CropCycleId { get; set; }
    public Guid CreatedByUserId { get; set; }
    public Point? Location { get; set; }
    public string? Note { get; set; }
    public string? PhotoKey { get; set; }
    public DateTimeOffset? SyncedAt { get; set; }

    public ImageAnalysis? ImageAnalysis { get; set; }
}

public class ImageAnalysis : Entity
{
    public Guid ObservationId { get; set; }
    public string? Diagnosis { get; set; }        // JSON estructurado devuelto por la IA
    public string? Severity { get; set; }
    public double? Confidence { get; set; }
    public string? Recommendations { get; set; }
    public DateTimeOffset? AnalyzedAt { get; set; }
}

public class HarvestResult : Entity
{
    public Guid CropCycleId { get; set; }
    public double YieldKg { get; set; }
    public string? Quality { get; set; }
    public double PostHarvestLossKg { get; set; }
    public decimal TotalCost { get; set; }
    public decimal RevenueEst { get; set; }
    public string? Notes { get; set; }
}

/// <summary>Registro fenológico de la etapa de monitoreo (etapa 5).</summary>
public class PhenologyRecord : Entity
{
    public Guid CropCycleId { get; set; }
    public DateOnly RecordedAt { get; set; }
    public PhenoStage Stage { get; set; }
    public double? PlantHeightCm { get; set; }
    public double? PestIncidencePct { get; set; }
    public double? DiseaseIncidencePct { get; set; }
    public string? Notes { get; set; }
}
