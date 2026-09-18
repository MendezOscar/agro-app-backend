using AgroApp.Domain;
using AgroApp.Infrastructure.Identity;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using NetTopologySuite.Geometries;

namespace AgroApp.Api;

/// <summary>Aplica migraciones y siembra los datos de Finca Naara (café en Marcala, La Paz).
/// Montos en lempiras; el calendario sigue la cosecha hondureña (diciembre a marzo).</summary>
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
        var owner = await CreateUserAsync(users, org.Id, "owner@naara.com", "Luisa Mejía", UserRole.Owner);
        var agronomo = await CreateUserAsync(users, org.Id, "agronomo@naara.com", "Carlos Zelaya", UserRole.AgronomistManager);
        var tecnico = await CreateUserAsync(users, org.Id, "tecnico@naara.com", "Diana Lanza", UserRole.AgronomistWorker);
        await CreateUserAsync(users, org.Id, "jornalero@naara.com", "Jairo Bautista", UserRole.Laborer);

        // --- Finca y lotes (Marcala, La Paz; ~14.4 ha) -------------------------------
        var farm = new Farm
        {
            OrganizationId = org.Id,
            Name = OrgName,
            AreaHa = 14.4,
            Location = f.CreatePoint(new Coordinate(-88.0260, 14.1415)),
            Boundary = Box(f, -88.0280, 14.1400, -88.0240, 14.1430)
        };
        db.Farms.Add(farm);

        var elOcotal = new Plot
        {
            FarmId = farm.Id, Name = "Lote El Ocotal", AreaHa = 5.1, SoilType = "Franco arenoso",
            Boundary = Box(f, -88.0280, 14.1400, -88.0266, 14.1430)
        };
        var laQuebrada = new Plot
        {
            FarmId = farm.Id, Name = "Lote La Quebrada", AreaHa = 4.7, SoilType = "Franco",
            Boundary = Box(f, -88.0266, 14.1400, -88.0253, 14.1430)
        };
        var losNaranjos = new Plot
        {
            FarmId = farm.Id, Name = "Lote Los Naranjos", AreaHa = 4.6, SoilType = "Franco arcilloso",
            Boundary = Box(f, -88.0253, 14.1400, -88.0240, 14.1430)
        };
        db.Plots.AddRange(elOcotal, laQuebrada, losNaranjos);

        db.Analyses.AddRange(
            new Analysis { PlotId = elOcotal.Id, Kind = AnalysisKind.Soil, Ph = 5.2, N = 28, P = 9, K = 0.38, OrganicMatter = 8.4, Texture = "Franco arenoso", SampledAt = new DateOnly(2026, 3, 10) },
            new Analysis { PlotId = laQuebrada.Id, Kind = AnalysisKind.Soil, Ph = 5.6, N = 34, P = 12, K = 0.45, OrganicMatter = 10.1, Texture = "Franco", SampledAt = new DateOnly(2026, 3, 10) },
            new Analysis { PlotId = losNaranjos.Id, Kind = AnalysisKind.Soil, Ph = 4.9, N = 22, P = 7, K = 0.29, OrganicMatter = 6.8, Texture = "Franco arcilloso", SampledAt = new DateOnly(2026, 8, 20) },
            new Analysis { PlotId = elOcotal.Id, Kind = AnalysisKind.Water, Ph = 6.8, SampledAt = new DateOnly(2026, 5, 5) });

        // --- Insumos del almacén (precios en lempiras) -------------------------------
        var plantula = NewInput(org.Id, "Plántula de café Lempira", InputKind.Seed, "plántula", 3.50m, 1200, 200);
        var abono = NewInput(org.Id, "Fertilizante 18-5-15-6-2", InputKind.Fertilizer, "quintal (100 lb)", 1_600m, 60, 20);
        var urea = NewInput(org.Id, "Urea 46%", InputKind.Fertilizer, "quintal (100 lb)", 1_300m, 12, 20); // stock bajo a propósito
        var cal = NewInput(org.Id, "Cal dolomítica", InputKind.Fertilizer, "quintal (100 lb)", 180m, 30, 10);
        var fungicida = NewInput(org.Id, "Cyproconazol 10 SL", InputKind.Pesticide, "litro", 900m, 14, 5);
        var jornal = NewInput(org.Id, "Jornal de campo", InputKind.Labor, "jornal", 230m, 0, 0);
        var lata = NewInput(org.Id, "Recolección de café", InputKind.Labor, "lata (12.5 kg)", 50m, 0, 0);
        var guadana = NewInput(org.Id, "Guadañadora (alquiler)", InputKind.Machinery, "día", 400m, 0, 0);
        db.Inputs.AddRange(plantula, abono, urea, cal, fungicida, jornal, lata, guadana);

        // Pasos de beneficio del café que usa esta finca.
        db.HarvestStepTemplates.Add(new HarvestStepTemplate
        {
            OrganizationId = org.Id,
            Crop = Crop,
            Steps = new List<string> { "Corte", "Despulpe", "Fermentado", "Lavado", "Secado", "Trilla", "Clasificación", "Empacado" }
        });

        // === Ciclo 2026/2027: El Ocotal, variedad Lempira, en manejo =================
        var ciclo1 = new CropCycle
        {
            PlotId = elOcotal.Id, Crop = Crop, Variety = "Lempira",
            Status = CropCycleStatus.Active,
            PlannedStart = new DateOnly(2026, 4, 1), ActualStart = new DateOnly(2026, 4, 8),
            PlannedEnd = new DateOnly(2027, 4, 15)
        };
        db.CropCycles.Add(ciclo1);

        var c1Planning = NewStage(ciclo1.Id, StageKind.Planning, StageStatus.Completed, "2026-03-20", "2026-04-05", "Plan de sostenimiento del ciclo 2026/2027 sobre 5.1 ha.");
        var c1Suelo = NewStage(ciclo1.Id, StageKind.SoilPrep, StageStatus.Completed, "2026-04-06", "2026-04-25", "Encalado con 9 qq/mz por el pH de 5.2.");
        var c1Siembra = NewStage(ciclo1.Id, StageKind.Sowing, StageStatus.Completed, "2026-04-26", "2026-05-15", "Resiembra de 900 plántulas a 1.5 x 1.0 m.");
        var c1Manejo = NewStage(ciclo1.Id, StageKind.CropManagement, StageStatus.InProgress, "2026-05-16", null, "Dos fertilizaciones aplicadas; falta la de octubre.");
        var c1Monitoreo = NewStage(ciclo1.Id, StageKind.Monitoring, StageStatus.InProgress, "2026-06-01", null, "Monitoreo quincenal de roya y broca.");
        var c1Cosecha = NewStage(ciclo1.Id, StageKind.Harvest, StageStatus.Pending, null, null, "Cosecha prevista de diciembre a marzo.");
        var c1Pos = NewStage(ciclo1.Id, StageKind.PostHarvest, StageStatus.Pending, null, null, null);
        var c1Eval = NewStage(ciclo1.Id, StageKind.Evaluation, StageStatus.Pending, null, null, null);
        db.Stages.AddRange(c1Planning, c1Suelo, c1Siembra, c1Manejo, c1Monitoreo, c1Cosecha, c1Pos, c1Eval);

        db.WorkTasks.AddRange(
            NewTask(c1Suelo.Id, "Aplicar cal dolomítica", "9 qq/mz en todo el lote", agronomo.Id, WorkTaskStatus.Done, "2026-04-18", "2026-04-17"),
            NewTask(c1Siembra.Id, "Resembrar plántulas Lempira", "900 plántulas en los claros", tecnico.Id, WorkTaskStatus.Done, "2026-05-10", "2026-05-09"),
            NewTask(c1Manejo.Id, "Segunda fertilización (urea)", "Refuerzo nitrogenado, 120 g/planta", tecnico.Id, WorkTaskStatus.Done, "2026-07-20", "2026-07-22"),
            NewTask(c1Manejo.Id, "Tercera fertilización", "Aplicar 18-5-15-6-2 antes de las lluvias de octubre", tecnico.Id, WorkTaskStatus.Todo, "2026-10-10", null),
            NewTask(c1Monitoreo.Id, "Muestreo de broca", "30 árboles al azar, registrar % de infestación", tecnico.Id, WorkTaskStatus.InProgress, "2026-09-25", null),
            NewTask(c1Cosecha.Id, "Contratar cuadrilla de recolección", "Estimar 2.400 latas para el primer pase", owner.Id, WorkTaskStatus.Todo, "2026-11-10", null),
            NewTask(c1Cosecha.Id, "Revisar despulpadora y patios", "Mantenimiento antes de que entre la cosecha", agronomo.Id, WorkTaskStatus.Todo, "2026-11-20", null));

        db.CostEntries.AddRange(
            NewCost(ciclo1.Id, c1Suelo.Id, cal.Id, CostKind.Input, "Cal dolomítica", 45m, 180m, "2026-04-15"),
            NewCost(ciclo1.Id, c1Siembra.Id, plantula.Id, CostKind.Input, "Plántulas Lempira para resiembra", 900m, 3.50m, "2026-04-30"),
            NewCost(ciclo1.Id, c1Manejo.Id, abono.Id, CostKind.Input, "Primera fertilización 18-5-15-6-2", 70m, 1_600m, "2026-05-20"),
            NewCost(ciclo1.Id, c1Manejo.Id, urea.Id, CostKind.Input, "Refuerzo nitrogenado", 40m, 1_300m, "2026-07-22"),
            NewCost(ciclo1.Id, c1Manejo.Id, jornal.Id, CostKind.Labor, "Desyerbas, plateos y poda de sombra", 60m, 230m, "2026-08-31"),
            NewCost(ciclo1.Id, c1Manejo.Id, guadana.Id, CostKind.Machinery, "Alquiler de guadaña", 8m, 400m, "2026-08-31"),
            NewCost(ciclo1.Id, c1Monitoreo.Id, fungicida.Id, CostKind.Input, "Control preventivo de roya", 12m, 900m, "2026-08-14"));

        db.PhenologyRecords.AddRange(
            NewPheno(ciclo1.Id, "2026-05-05", PhenoStage.Vegetative, 95, 1.5, 2.0, "Rebrote parejo después de la poda."),
            NewPheno(ciclo1.Id, "2026-05-28", PhenoStage.Flowering, 102, 2.0, 3.0, "Floración principal tras las primeras lluvias de mayo."),
            NewPheno(ciclo1.Id, "2026-06-18", PhenoStage.Germination, 9, 0, 0, "Plántulas de resiembra prendidas al 95%."),
            NewPheno(ciclo1.Id, "2026-07-02", PhenoStage.FruitSet, 110, 3.2, 3.8, "Cuaje alto; se refuerza el monitoreo de broca."),
            NewPheno(ciclo1.Id, "2026-09-10", PhenoStage.Maturation, 118, 4.1, 5.5, "Llenado de grano avanzado; cosecha esperada desde diciembre."));

        db.Observations.AddRange(
            new Observation { CropCycleId = ciclo1.Id, CreatedByUserId = tecnico.Id, Note = "Focos de roya en el borde norte, hojas con esporulación amarilla.", Location = f.CreatePoint(new Coordinate(-88.0274, 14.1425)) },
            new Observation { CropCycleId = ciclo1.Id, CreatedByUserId = tecnico.Id, Note = "Broca por encima del umbral en 3 de 30 árboles muestreados.", Location = f.CreatePoint(new Coordinate(-88.0271, 14.1409)) },
            new Observation { CropCycleId = ciclo1.Id, CreatedByUserId = agronomo.Id, Note = "Sombra de guama muy cerrada en la franja baja; programar regulación.", Location = f.CreatePoint(new Coordinate(-88.0277, 14.1403)) });

        // Pasos de beneficio materializados desde la plantilla, aún sin iniciar.
        var pasos = new[] { "Corte", "Despulpe", "Fermentado", "Lavado", "Secado", "Trilla", "Clasificación", "Empacado" };
        for (var i = 0; i < pasos.Length; i++)
            db.HarvestSteps.Add(NewStep(ciclo1.Id, i + 1, pasos[i], StageStatus.Pending, null, null, null, null));

        // === Ciclo 2025/2026: La Quebrada, Catuaí, cerrado con resultados ============
        var ciclo2 = new CropCycle
        {
            PlotId = laQuebrada.Id, Crop = Crop, Variety = "Catuaí",
            Status = CropCycleStatus.Closed,
            PlannedStart = new DateOnly(2025, 4, 1), ActualStart = new DateOnly(2025, 4, 5),
            PlannedEnd = new DateOnly(2026, 4, 15), ActualEnd = new DateOnly(2026, 4, 10),
            YieldKg = 6100
        };
        db.CropCycles.Add(ciclo2);

        var c2Stages = new[]
        {
            NewStage(ciclo2.Id, StageKind.Planning, StageStatus.Completed, "2025-03-20", "2025-04-04", null),
            NewStage(ciclo2.Id, StageKind.SoilPrep, StageStatus.Completed, "2025-04-05", "2025-04-28", null),
            NewStage(ciclo2.Id, StageKind.Sowing, StageStatus.Completed, "2025-04-29", "2025-05-20", null),
            NewStage(ciclo2.Id, StageKind.CropManagement, StageStatus.Completed, "2025-05-21", "2025-10-30", null),
            NewStage(ciclo2.Id, StageKind.Monitoring, StageStatus.Completed, "2025-06-01", "2026-02-20", "Incidencia de roya controlada por debajo del 5%."),
            NewStage(ciclo2.Id, StageKind.Harvest, StageStatus.Completed, "2025-12-05", "2026-03-10", "Tres pases de recolección."),
            NewStage(ciclo2.Id, StageKind.PostHarvest, StageStatus.Completed, "2025-12-08", "2026-03-28", "Secado en patio y marquesina hasta 11.5% de humedad."),
            NewStage(ciclo2.Id, StageKind.Evaluation, StageStatus.Completed, "2026-03-29", "2026-04-10", "Margen positivo; se repite el plan de fertilización.")
        };
        db.Stages.AddRange(c2Stages);

        db.CostEntries.AddRange(
            NewCost(ciclo2.Id, c2Stages[3].Id, abono.Id, CostKind.Input, "Fertilización completa del ciclo", 135m, 1_600m, "2025-08-15"),
            NewCost(ciclo2.Id, c2Stages[3].Id, jornal.Id, CostKind.Labor, "Poda, desyerbas y regulación de sombra", 180m, 230m, "2025-10-30"),
            NewCost(ciclo2.Id, c2Stages[4].Id, fungicida.Id, CostKind.Input, "Fitosanitarios del ciclo", 24m, 900m, "2025-09-10"),
            NewCost(ciclo2.Id, c2Stages[5].Id, lata.Id, CostKind.Labor, "Recolección (tres pases)", 2440m, 50m, "2026-02-28"),
            NewCost(ciclo2.Id, c2Stages[6].Id, null, CostKind.Other, "Beneficio y secado", 1m, 48_000m, "2026-03-20"),
            NewCost(ciclo2.Id, c2Stages[6].Id, null, CostKind.Other, "Transporte a la cooperativa", 1m, 12_000m, "2026-03-30"));

        db.HarvestResults.Add(new HarvestResult
        {
            CropCycleId = ciclo2.Id,
            YieldKg = 6100,
            Quality = "Pergamino seco, taza 85 puntos SCA (denominación Marcala)",
            PostHarvestLossKg = 150,
            TotalCost = 461_000m,
            RevenueEst = 699_400m,
            Notes = "134.5 qq de pergamino a L 5.200 el quintal, precio de la cooperativa."
        });

        db.HarvestSteps.AddRange(
            NewStep(ciclo2.Id, 1, "Corte", StageStatus.Completed, "2026-02-28", 30500, 30500, "Tres pases, solo fruto maduro."),
            NewStep(ciclo2.Id, 2, "Despulpe", StageStatus.Completed, "2026-02-28", 30500, 14400, null),
            NewStep(ciclo2.Id, 3, "Fermentado", StageStatus.Completed, "2026-03-01", 14400, 14100, "18 a 20 horas en pila."),
            NewStep(ciclo2.Id, 4, "Lavado", StageStatus.Completed, "2026-03-01", 14100, 13700, null),
            NewStep(ciclo2.Id, 5, "Secado", StageStatus.Completed, "2026-03-18", 13700, 6250, "Patio y marquesina, 14 días."),
            NewStep(ciclo2.Id, 6, "Trilla", StageStatus.Completed, "2026-03-24", 6250, 4980, "Conversión a café oro."),
            NewStep(ciclo2.Id, 7, "Clasificación", StageStatus.Completed, "2026-03-26", 4980, 4830, "Se descarta el grano de segunda."),
            NewStep(ciclo2.Id, 8, "Empacado", StageStatus.Completed, "2026-03-28", 4830, 4830, "Sacos de 69 kg para exportación."));

        db.PhenologyRecords.AddRange(
            NewPheno(ciclo2.Id, "2025-05-25", PhenoStage.Flowering, 145, 2.5, 4.0, null),
            NewPheno(ciclo2.Id, "2025-08-20", PhenoStage.FruitSet, 152, 3.0, 4.5, null),
            NewPheno(ciclo2.Id, "2025-11-28", PhenoStage.Maturation, 158, 3.8, 4.8, null));

        // === Ciclo 2027/2028: Los Naranjos, renovación planeada ======================
        var ciclo3 = new CropCycle
        {
            PlotId = losNaranjos.Id, Crop = Crop, Variety = "Parainema",
            Status = CropCycleStatus.Planned,
            PlannedStart = new DateOnly(2027, 4, 1), PlannedEnd = new DateOnly(2028, 3, 31)
        };
        db.CropCycles.Add(ciclo3);

        var c3Planning = NewStage(ciclo3.Id, StageKind.Planning, StageStatus.InProgress, "2026-09-01", null, "Renovación por recepa tras la cosecha 2026/2027; el análisis dio pH 4.9.");
        db.Stages.Add(c3Planning);
        foreach (var kind in new[] { StageKind.SoilPrep, StageKind.Sowing, StageKind.CropManagement, StageKind.Monitoring, StageKind.Harvest, StageKind.PostHarvest, StageKind.Evaluation })
            db.Stages.Add(NewStage(ciclo3.Id, kind, StageStatus.Pending, null, null, null));

        db.WorkTasks.AddRange(
            NewTask(c3Planning.Id, "Cotizar cal y fertilizantes", "Tres proveedores de Marcala y La Esperanza", owner.Id, WorkTaskStatus.Done, "2026-09-10", "2026-09-09"),
            NewTask(c3Planning.Id, "Definir densidad de siembra", "Evaluar 1.5 x 1.0 m contra 1.6 x 1.0 m", agronomo.Id, WorkTaskStatus.InProgress, "2026-09-30", null));

        db.CostEntries.Add(NewCost(ciclo3.Id, c3Planning.Id, null, CostKind.Other, "Análisis de suelo del lote", 1m, 1_200m, "2026-08-20"));

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
