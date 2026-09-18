using AgroApp.Domain;
using AgroApp.Infrastructure.Identity;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using NetTopologySuite.Geometries;

namespace AgroApp.Api;

/// <summary>Aplica migraciones y siembra los datos de Finca Naara (producción de café).</summary>
public static class DbSeeder
{
    private const string OrgName = "Finca Naara";
    private const string SeedPassword = "Naara2026*";
    private const string Crop = "Café";

    /// <summary>Crea los roles de Identity que falten (idempotente, seguro en producción).</summary>
    public static async Task EnsureRolesAsync(IServiceProvider sp)
    {
        var roleMgr = sp.GetRequiredService<RoleManager<IdentityRole<Guid>>>();
        foreach (var role in Enum.GetNames<UserRole>())
            if (!await roleMgr.RoleExistsAsync(role))
                await roleMgr.CreateAsync(new IdentityRole<Guid>(role));
    }

    public static async Task MigrateAndSeedAsync(IServiceProvider sp)
    {
        var db = sp.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();

        await EnsureRolesAsync(sp);

        if (await db.Organizations.AnyAsync(o => o.Name == OrgName)) return; // ya sembrado

        var f = NetTopologySuite.NtsGeometryServices.Instance.CreateGeometryFactory(4326);

        // --- Organización y usuarios -------------------------------------------------
        var org = new Organization { Name = OrgName };
        db.Organizations.Add(org);
        await db.SaveChangesAsync();

        var users = sp.GetRequiredService<UserManager<ApplicationUser>>();
        var owner = await CreateUserAsync(users, org.Id, "owner@naara.com", "Luisa Naranjo", UserRole.Owner);
        var agronomo = await CreateUserAsync(users, org.Id, "agronomo@naara.com", "Carlos Restrepo", UserRole.AgronomistManager);
        var tecnico = await CreateUserAsync(users, org.Id, "tecnico@naara.com", "Diana Ospina", UserRole.AgronomistWorker);
        await CreateUserAsync(users, org.Id, "jornalero@naara.com", "Jairo Quintero", UserRole.Laborer);

        // --- Finca y lotes (suroeste antioqueño, ~14.8 ha) ---------------------------
        var farm = new Farm
        {
            OrganizationId = org.Id,
            Name = OrgName,
            AreaHa = 14.8,
            Location = f.CreatePoint(new Coordinate(-75.9680, 5.9515)),
            Boundary = Box(f, -75.9700, 5.9500, -75.9660, 5.9530)
        };
        db.Farms.Add(farm);

        var laCeiba = new Plot
        {
            FarmId = farm.Id, Name = "Lote La Ceiba", AreaHa = 5.2, SoilType = "Franco arenoso",
            Boundary = Box(f, -75.9700, 5.9500, -75.9686, 5.9530)
        };
        var elGuamo = new Plot
        {
            FarmId = farm.Id, Name = "Lote El Guamo", AreaHa = 4.8, SoilType = "Franco",
            Boundary = Box(f, -75.9686, 5.9500, -75.9673, 5.9530)
        };
        var laCanada = new Plot
        {
            FarmId = farm.Id, Name = "Lote La Cañada", AreaHa = 4.8, SoilType = "Franco arcilloso",
            Boundary = Box(f, -75.9673, 5.9500, -75.9660, 5.9530)
        };
        db.Plots.AddRange(laCeiba, elGuamo, laCanada);

        db.Analyses.AddRange(
            new Analysis { PlotId = laCeiba.Id, Kind = AnalysisKind.Soil, Ph = 5.2, N = 28, P = 9, K = 0.38, OrganicMatter = 8.4, Texture = "Franco arenoso", SampledAt = new DateOnly(2026, 1, 20) },
            new Analysis { PlotId = elGuamo.Id, Kind = AnalysisKind.Soil, Ph = 5.6, N = 34, P = 12, K = 0.45, OrganicMatter = 10.1, Texture = "Franco", SampledAt = new DateOnly(2026, 1, 20) },
            new Analysis { PlotId = laCanada.Id, Kind = AnalysisKind.Soil, Ph = 4.9, N = 22, P = 7, K = 0.29, OrganicMatter = 6.8, Texture = "Franco arcilloso", SampledAt = new DateOnly(2026, 8, 12) },
            new Analysis { PlotId = laCeiba.Id, Kind = AnalysisKind.Water, Ph = 6.8, SampledAt = new DateOnly(2026, 3, 5) });

        // --- Insumos del almacén -----------------------------------------------------
        var chapola = NewInput(org.Id, "Café Castillo (chapola)", InputKind.Seed, "plántula", 950m, 1200, 200);
        var abono = NewInput(org.Id, "Fertilizante 17-6-18-2", InputKind.Fertilizer, "bulto 50 kg", 130_000m, 18, 6);
        var urea = NewInput(org.Id, "Urea 46%", InputKind.Fertilizer, "bulto 50 kg", 118_000m, 4, 6); // stock bajo a propósito
        var fungicida = NewInput(org.Id, "Cyproconazol 10 SL", InputKind.Pesticide, "litro", 95_000m, 9, 3);
        var jornalRec = NewInput(org.Id, "Jornal de recolección", InputKind.Labor, "jornal", 65_000m, 0, 0);
        var jornalCam = NewInput(org.Id, "Jornal de campo", InputKind.Labor, "jornal", 60_000m, 0, 0);
        var guadana = NewInput(org.Id, "Guadañadora (alquiler)", InputKind.Machinery, "día", 45_000m, 0, 0);
        db.Inputs.AddRange(chapola, abono, urea, fungicida, jornalRec, jornalCam, guadana);

        // Pasos de beneficio del café que usa esta finca.
        db.HarvestStepTemplates.Add(new HarvestStepTemplate
        {
            OrganizationId = org.Id,
            Crop = Crop,
            Steps = new List<string> { "Corte", "Despulpe", "Fermentado", "Lavado", "Secado", "Trilla", "Clasificación", "Empacado" }
        });

        // === Ciclo 1: La Ceiba, Castillo, en cosecha =================================
        var ciclo1 = new CropCycle
        {
            PlotId = laCeiba.Id, Crop = Crop, Variety = "Castillo",
            Status = CropCycleStatus.Active,
            PlannedStart = new DateOnly(2026, 1, 15), ActualStart = new DateOnly(2026, 1, 18),
            PlannedEnd = new DateOnly(2026, 12, 15)
        };
        db.CropCycles.Add(ciclo1);

        var c1Planning = NewStage(ciclo1.Id, StageKind.Planning, StageStatus.Completed, "2026-01-15", "2026-01-31", "Plan de renovación por zoca en 2 ha y sostenimiento del resto.");
        var c1Suelo = NewStage(ciclo1.Id, StageKind.SoilPrep, StageStatus.Completed, "2026-02-01", "2026-02-20", "Encalado con 1.5 t/ha según análisis (pH 5.2).");
        var c1Siembra = NewStage(ciclo1.Id, StageKind.Sowing, StageStatus.Completed, "2026-02-21", "2026-03-10", "Resiembra de 900 chapolas a 1.4 x 1.0 m.");
        var c1Manejo = NewStage(ciclo1.Id, StageKind.CropManagement, StageStatus.Completed, "2026-03-11", "2026-08-31", "Tres desyerbas y dos fertilizaciones edáficas.");
        var c1Monitoreo = NewStage(ciclo1.Id, StageKind.Monitoring, StageStatus.InProgress, "2026-04-01", null, "Monitoreo quincenal de broca y roya.");
        var c1Cosecha = NewStage(ciclo1.Id, StageKind.Harvest, StageStatus.InProgress, "2026-09-05", null, "Cosecha principal: primer pase de recolección.");
        var c1Pos = NewStage(ciclo1.Id, StageKind.PostHarvest, StageStatus.Pending, null, null, null);
        var c1Eval = NewStage(ciclo1.Id, StageKind.Evaluation, StageStatus.Pending, null, null, null);
        db.Stages.AddRange(c1Planning, c1Suelo, c1Siembra, c1Manejo, c1Monitoreo, c1Cosecha, c1Pos, c1Eval);

        db.WorkTasks.AddRange(
            NewTask(c1Suelo.Id, "Aplicar cal dolomita", "1.5 t/ha en todo el lote", agronomo.Id, WorkTaskStatus.Done, "2026-02-12", "2026-02-11"),
            NewTask(c1Siembra.Id, "Resembrar chapolas", "900 plántulas en los claros", tecnico.Id, WorkTaskStatus.Done, "2026-03-05", "2026-03-04"),
            NewTask(c1Manejo.Id, "Segunda fertilización", "17-6-18-2, 120 g/planta", tecnico.Id, WorkTaskStatus.Done, "2026-07-20", "2026-07-22"),
            NewTask(c1Monitoreo.Id, "Muestreo de broca", "30 árboles al azar, registrar % de infestación", tecnico.Id, WorkTaskStatus.InProgress, "2026-09-20", null),
            NewTask(c1Cosecha.Id, "Primer pase de recolección", "Solo fruto maduro, cuadrilla de 8 personas", owner.Id, WorkTaskStatus.InProgress, "2026-09-25", null),
            NewTask(c1Cosecha.Id, "Calibrar despulpadora", "Revisar camisas antes del segundo pase", agronomo.Id, WorkTaskStatus.Todo, "2026-09-28", null));

        db.CostEntries.AddRange(
            NewCost(ciclo1.Id, c1Suelo.Id, null, CostKind.Input, "Cal dolomita", 8m, 38_000m, "2026-02-10"),
            NewCost(ciclo1.Id, c1Siembra.Id, chapola.Id, CostKind.Input, "Chapolas Castillo para resiembra", 900m, 950m, "2026-02-25"),
            NewCost(ciclo1.Id, c1Manejo.Id, abono.Id, CostKind.Input, "Fertilización edáfica 17-6-18-2", 12m, 130_000m, "2026-04-18"),
            NewCost(ciclo1.Id, c1Manejo.Id, urea.Id, CostKind.Input, "Refuerzo nitrogenado", 8m, 118_000m, "2026-07-22"),
            NewCost(ciclo1.Id, c1Manejo.Id, jornalCam.Id, CostKind.Labor, "Desyerbas y plateos", 45m, 60_000m, "2026-06-30"),
            NewCost(ciclo1.Id, c1Manejo.Id, guadana.Id, CostKind.Machinery, "Alquiler de guadaña", 6m, 45_000m, "2026-06-30"),
            NewCost(ciclo1.Id, c1Monitoreo.Id, fungicida.Id, CostKind.Input, "Control preventivo de roya", 4m, 95_000m, "2026-08-14"),
            NewCost(ciclo1.Id, c1Cosecha.Id, jornalRec.Id, CostKind.Labor, "Recolección primer pase", 60m, 65_000m, "2026-09-15"));

        db.PhenologyRecords.AddRange(
            NewPheno(ciclo1.Id, "2026-03-15", PhenoStage.Germination, 8, 0, 0, "Chapolas prendidas al 96%."),
            NewPheno(ciclo1.Id, "2026-05-10", PhenoStage.Vegetative, 42, 1.5, 2.0, "Buen desarrollo foliar tras la fertilización."),
            NewPheno(ciclo1.Id, "2026-06-20", PhenoStage.Flowering, 68, 2.0, 3.5, "Floración principal pareja después de las lluvias."),
            NewPheno(ciclo1.Id, "2026-07-25", PhenoStage.FruitSet, 84, 3.2, 4.0, "Cuaje alto; se refuerza el monitoreo de broca."),
            NewPheno(ciclo1.Id, "2026-09-05", PhenoStage.Maturation, 96, 4.1, 5.5, "Maduración despareja en la parte alta del lote."));

        db.Observations.AddRange(
            new Observation { CropCycleId = ciclo1.Id, CreatedByUserId = tecnico.Id, Note = "Focos de roya en el borde norte, hojas con esporulación amarilla.", Location = f.CreatePoint(new Coordinate(-75.9694, 5.9525)) },
            new Observation { CropCycleId = ciclo1.Id, CreatedByUserId = tecnico.Id, Note = "Broca por encima del umbral en 3 de 30 árboles muestreados.", Location = f.CreatePoint(new Coordinate(-75.9691, 5.9509)) },
            new Observation { CropCycleId = ciclo1.Id, CreatedByUserId = agronomo.Id, Note = "Cereza madura lista para el segundo pase en la franja baja.", Location = f.CreatePoint(new Coordinate(-75.9697, 5.9503)) });

        db.HarvestSteps.AddRange(
            NewStep(ciclo1.Id, 1, "Corte", StageStatus.Completed, "2026-09-08", 3100, 3100, "Primer pase, solo maduro."),
            NewStep(ciclo1.Id, 2, "Despulpe", StageStatus.Completed, "2026-09-08", 3100, 1480, "Rendimiento normal de cereza a baba."),
            NewStep(ciclo1.Id, 3, "Fermentado", StageStatus.InProgress, null, 1480, null, "18 horas en tanque."),
            NewStep(ciclo1.Id, 4, "Lavado", StageStatus.Pending, null, null, null, null),
            NewStep(ciclo1.Id, 5, "Secado", StageStatus.Pending, null, null, null, null),
            NewStep(ciclo1.Id, 6, "Trilla", StageStatus.Pending, null, null, null, null),
            NewStep(ciclo1.Id, 7, "Clasificación", StageStatus.Pending, null, null, null, null),
            NewStep(ciclo1.Id, 8, "Empacado", StageStatus.Pending, null, null, null, null));

        // === Ciclo 2: El Guamo, Caturra, cerrado con resultados ======================
        var ciclo2 = new CropCycle
        {
            PlotId = elGuamo.Id, Crop = Crop, Variety = "Caturra",
            Status = CropCycleStatus.Closed,
            PlannedStart = new DateOnly(2025, 1, 20), ActualStart = new DateOnly(2025, 2, 1),
            PlannedEnd = new DateOnly(2025, 12, 10), ActualEnd = new DateOnly(2025, 11, 30),
            YieldKg = 1640
        };
        db.CropCycles.Add(ciclo2);

        var c2Stages = new[]
        {
            NewStage(ciclo2.Id, StageKind.Planning, StageStatus.Completed, "2025-01-20", "2025-01-31", null),
            NewStage(ciclo2.Id, StageKind.SoilPrep, StageStatus.Completed, "2025-02-01", "2025-02-18", null),
            NewStage(ciclo2.Id, StageKind.Sowing, StageStatus.Completed, "2025-02-19", "2025-03-08", null),
            NewStage(ciclo2.Id, StageKind.CropManagement, StageStatus.Completed, "2025-03-09", "2025-08-30", null),
            NewStage(ciclo2.Id, StageKind.Monitoring, StageStatus.Completed, "2025-04-01", "2025-10-15", "Incidencia de roya controlada por debajo del 5%."),
            NewStage(ciclo2.Id, StageKind.Harvest, StageStatus.Completed, "2025-09-20", "2025-11-10", "Tres pases de recolección."),
            NewStage(ciclo2.Id, StageKind.PostHarvest, StageStatus.Completed, "2025-09-22", "2025-11-25", "Secado en marquesina, 11% de humedad."),
            NewStage(ciclo2.Id, StageKind.Evaluation, StageStatus.Completed, "2025-11-26", "2025-11-30", "Margen positivo; se repite el plan de fertilización.")
        };
        db.Stages.AddRange(c2Stages);

        db.CostEntries.AddRange(
            NewCost(ciclo2.Id, c2Stages[3].Id, abono.Id, CostKind.Input, "Fertilización completa del ciclo", 22m, 131_818.18m, "2025-05-15"),
            NewCost(ciclo2.Id, c2Stages[5].Id, jornalRec.Id, CostKind.Labor, "Recolección (tres pases)", 70m, 60_000m, "2025-10-30"),
            NewCost(ciclo2.Id, c2Stages[6].Id, null, CostKind.Other, "Beneficio y secado", 1m, 1_450_000m, "2025-11-20"),
            NewCost(ciclo2.Id, c2Stages[4].Id, fungicida.Id, CostKind.Input, "Fitosanitarios del ciclo", 8m, 97_500m, "2025-07-10"),
            NewCost(ciclo2.Id, c2Stages[6].Id, null, CostKind.Other, "Transporte a la cooperativa", 1m, 520_000m, "2025-11-28"));

        db.HarvestResults.Add(new HarvestResult
        {
            CropCycleId = ciclo2.Id,
            YieldKg = 1640,
            Quality = "Pergamino seco, taza 84 puntos SCA",
            PostHarvestLossKg = 120,
            TotalCost = 9_850_000m,
            RevenueEst = 18_040_000m,
            Notes = "Precio de referencia 11.000 COP/kg de pergamino seco."
        });

        db.HarvestSteps.AddRange(
            NewStep(ciclo2.Id, 1, "Corte", StageStatus.Completed, "2025-10-05", 8200, 8200, "Cereza madura."),
            NewStep(ciclo2.Id, 2, "Despulpe", StageStatus.Completed, "2025-10-05", 8200, 3900, null),
            NewStep(ciclo2.Id, 3, "Fermentado", StageStatus.Completed, "2025-10-06", 3900, 3820, "20 horas."),
            NewStep(ciclo2.Id, 4, "Lavado", StageStatus.Completed, "2025-10-06", 3820, 3700, null),
            NewStep(ciclo2.Id, 5, "Secado", StageStatus.Completed, "2025-10-18", 3700, 1760, "Marquesina, 12 días."),
            NewStep(ciclo2.Id, 6, "Trilla", StageStatus.Completed, "2025-11-12", 1760, 1700, null),
            NewStep(ciclo2.Id, 7, "Clasificación", StageStatus.Completed, "2025-11-18", 1700, 1640, "Se descarta pasilla."),
            NewStep(ciclo2.Id, 8, "Empacado", StageStatus.Completed, "2025-11-22", 1640, 1640, "Sacos de 70 kg."));

        db.PhenologyRecords.AddRange(
            NewPheno(ciclo2.Id, "2025-06-15", PhenoStage.Flowering, 145, 2.5, 4.0, null),
            NewPheno(ciclo2.Id, "2025-08-20", PhenoStage.FruitSet, 152, 3.0, 4.5, null),
            NewPheno(ciclo2.Id, "2025-10-01", PhenoStage.Maturation, 158, 3.8, 4.8, null));

        // === Ciclo 3: La Cañada, renovación planeada =================================
        var ciclo3 = new CropCycle
        {
            PlotId = laCanada.Id, Crop = Crop, Variety = "Colombia",
            Status = CropCycleStatus.Planned,
            PlannedStart = new DateOnly(2026, 10, 15), PlannedEnd = new DateOnly(2027, 9, 30)
        };
        db.CropCycles.Add(ciclo3);

        var c3Planning = NewStage(ciclo3.Id, StageKind.Planning, StageStatus.InProgress, "2026-09-01", null, "Renovación por siembra nueva tras el análisis de suelo (pH 4.9).");
        db.Stages.Add(c3Planning);
        foreach (var kind in new[] { StageKind.SoilPrep, StageKind.Sowing, StageKind.CropManagement, StageKind.Monitoring, StageKind.Harvest, StageKind.PostHarvest, StageKind.Evaluation })
            db.Stages.Add(NewStage(ciclo3.Id, kind, StageStatus.Pending, null, null, null));

        db.WorkTasks.AddRange(
            NewTask(c3Planning.Id, "Cotizar cal y fertilizantes", "Tres proveedores de la zona", owner.Id, WorkTaskStatus.Done, "2026-09-10", "2026-09-09"),
            NewTask(c3Planning.Id, "Definir densidad de siembra", "Evaluar 1.4 x 1.0 m contra 1.5 x 1.0 m", agronomo.Id, WorkTaskStatus.InProgress, "2026-09-30", null));

        db.CostEntries.Add(NewCost(ciclo3.Id, c3Planning.Id, null, CostKind.Other, "Análisis de suelo del lote", 1m, 180_000m, "2026-08-12"));

        await db.SaveChangesAsync();
    }

    // --- Helpers -----------------------------------------------------------------

    private static async Task<ApplicationUser> CreateUserAsync(
        UserManager<ApplicationUser> users, Guid orgId, string email, string fullName, UserRole role)
    {
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            UserName = email,
            Email = email,
            EmailConfirmed = true,
            FullName = fullName,
            OrganizationId = orgId,
            Role = role
        };
        await users.CreateAsync(user, SeedPassword);
        await users.AddToRoleAsync(user, role.ToString());
        return user;
    }

    /// <summary>Polígono rectangular a partir de la esquina suroeste y la noreste.</summary>
    private static Polygon Box(GeometryFactory f, double minLon, double minLat, double maxLon, double maxLat) =>
        f.CreatePolygon(new[]
        {
            new Coordinate(minLon, minLat),
            new Coordinate(maxLon, minLat),
            new Coordinate(maxLon, maxLat),
            new Coordinate(minLon, maxLat),
            new Coordinate(minLon, minLat)
        });

    private static Input NewInput(Guid orgId, string name, InputKind kind, string unit, decimal unitCost, double stock, double minStock) =>
        new() { OrganizationId = orgId, Name = name, Kind = kind, Unit = unit, UnitCost = unitCost, StockQty = stock, MinStock = minStock };

    private static Stage NewStage(Guid cycleId, StageKind kind, StageStatus status, string? startedAt, string? completedAt, string? notes) =>
        new()
        {
            CropCycleId = cycleId, Kind = kind, Status = status, Notes = notes,
            StartedAt = Ts(startedAt), CompletedAt = Ts(completedAt)
        };

    private static WorkTask NewTask(Guid stageId, string title, string? description, Guid assignedTo, WorkTaskStatus status, string? dueDate, string? completedAt) =>
        new()
        {
            StageId = stageId, Title = title, Description = description, AssignedToUserId = assignedTo,
            Status = status, DueDate = dueDate is null ? null : DateOnly.Parse(dueDate), CompletedAt = Ts(completedAt)
        };

    private static CostEntry NewCost(Guid cycleId, Guid? stageId, Guid? inputId, CostKind kind, string description, decimal qty, decimal unitCost, string incurredAt) =>
        new()
        {
            CropCycleId = cycleId, StageId = stageId, InputId = inputId, Kind = kind, Description = description,
            Quantity = qty, UnitCost = unitCost, Total = Math.Round(qty * unitCost, 2), IncurredAt = Ts(incurredAt)!.Value
        };

    private static PhenologyRecord NewPheno(Guid cycleId, string recordedAt, PhenoStage stage, double heightCm, double pestPct, double diseasePct, string? notes) =>
        new()
        {
            CropCycleId = cycleId, RecordedAt = DateOnly.Parse(recordedAt), Stage = stage,
            PlantHeightCm = heightCm, PestIncidencePct = pestPct, DiseaseIncidencePct = diseasePct, Notes = notes
        };

    private static HarvestStep NewStep(Guid cycleId, int order, string name, StageStatus status, string? completedAt, double? qtyIn, double? qtyOut, string? notes) =>
        new()
        {
            CropCycleId = cycleId, Order = order, Name = name, Status = status, CompletedAt = Ts(completedAt),
            QtyIn = qtyIn, QtyOut = qtyOut, Unit = "kg", Notes = notes
        };

    private static DateTimeOffset? Ts(string? date) =>
        date is null ? null : new DateTimeOffset(DateTime.SpecifyKind(DateTime.Parse(date), DateTimeKind.Utc));
}
