namespace AgroApp.Domain;

public enum UserRole
{
    Owner = 0,
    AgronomistManager = 1,
    AgronomistWorker = 2
}

public enum CropCycleStatus
{
    Planned = 0,
    Active = 1,
    Harvested = 2,
    Closed = 3
}

/// <summary>Las 8 etapas del proceso agronómico.</summary>
public enum StageKind
{
    Planning = 0,
    SoilPrep = 1,
    Sowing = 2,
    CropManagement = 3,
    Monitoring = 4,
    Harvest = 5,
    PostHarvest = 6,
    Evaluation = 7
}

public enum StageStatus
{
    Pending = 0,
    InProgress = 1,
    Completed = 2
}

public enum WorkTaskStatus
{
    Todo = 0,
    InProgress = 1,
    Done = 2
}

public enum InputKind
{
    Seed = 0,
    Fertilizer = 1,
    Pesticide = 2,
    Machinery = 3,
    Labor = 4
}

public enum CostKind
{
    Labor = 0,
    Input = 1,
    Machinery = 2,
    Other = 3
}

public enum AnalysisKind
{
    Soil = 0,
    Water = 1
}
