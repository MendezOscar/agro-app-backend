# Modelo de dominio — AgroApp

Multi-tenant: **toda** entidad de negocio lleva `OrganizationId`. Los IDs son GUID generados
en cliente (UUID v4) para permitir creación offline sin colisiones.

## Entidades

### Organization
Tenant del dueño de finca. Raíz de aislamiento de datos.
- `Id`, `Name`, `CreatedAt`

### User (ASP.NET Identity)
Pertenece a una organización.
- `Id`, `OrganizationId`, `Email`, `FullName`, `Role`
- **Roles**: `Owner`, `AgronomistManager`, `AgronomistWorker`

### Farm (Finca)
- `Id`, `OrganizationId`, `Name`, `Location` (Point 4326), `Boundary` (Polygon 4326, opcional),
  `AreaHa` (calculada con PostGIS), `CreatedAt`

### Plot (Lote/Parcela)
Subdivisión de una finca.
- `Id`, `FarmId`, `Name`, `Boundary` (Polygon 4326), `AreaHa`, `SoilType`

### CropCycle (Cosecha / Ciclo) — agregado central
Un ciclo de cultivo sobre un lote.
- `Id`, `PlotId`, `Crop`, `Variety`, `Status` (`Planned`→`Active`→`Harvested`→`Closed`),
  `PlannedStart`, `ActualStart`, `PlannedEnd`, `ActualEnd`, `YieldKg` (final)

### Stage (Etapa)
Las 8 etapas del ciclo. Se crean al iniciar el CropCycle.
- `Id`, `CropCycleId`, `Kind` (enum de 8), `Status`, `StartedAt`, `CompletedAt`, `Notes`
- **Kind**: `Planning`, `SoilPrep`, `Sowing`, `CropManagement`, `Monitoring`, `Harvest`,
  `PostHarvest`, `Evaluation`

### Task (Tarea)
Trabajo dentro de una etapa, asignado a un agrónomo.
- `Id`, `StageId`, `Title`, `Description`, `AssignedToUserId`, `Status`
  (`Todo`/`InProgress`/`Done`), `DueDate`, `CompletedAt`

### Input (Insumo)
Catálogo por organización.
- `Id`, `OrganizationId`, `Name`, `Kind` (`Seed`/`Fertilizer`/`Pesticide`/`Machinery`/`Labor`),
  `Unit`, `UnitCost`

### CostEntry (Costo)
- `Id`, `CropCycleId`, `TaskId?`, `InputId?`, `Kind`, `Description`, `Quantity`, `UnitCost`,
  `Total`, `IncurredAt`

### Analysis (Suelo/Agua) — etapa 1
- `Id`, `PlotId`, `Kind` (`Soil`/`Water`), `Ph`, `N`, `P`, `K`, `OrganicMatter`, `Texture`,
  `SampledAt`

### Observation (Monitoreo) — etapa 5, offline
- `Id`, `CropCycleId`, `CreatedByUserId`, `Location` (Point 4326), `Note`, `PhotoKey`
  (clave en S3), `CreatedAt`, `SyncedAt`

### ImageAnalysis (IA)
Resultado de Claude vision sobre la foto de una Observation.
- `Id`, `ObservationId`, `Diagnosis` (JSON: plaga/enfermedad/estado), `Severity`,
  `Confidence`, `Recommendations`, `AnalyzedAt`

### HarvestResult — etapas 6-8
- `Id`, `CropCycleId`, `YieldKg`, `Quality`, `PostHarvestLossKg`, `TotalCost`, `RevenueEst`,
  `Notes`

## Relaciones (resumen)

```
Organization 1─* User
Organization 1─* Farm 1─* Plot 1─* CropCycle 1─* Stage 1─* Task
                                   CropCycle 1─* CostEntry
                                   CropCycle 1─* Observation 1─1 ImageAnalysis
                                   CropCycle 1─1 HarvestResult
Plot 1─* Analysis
Organization 1─* Input
```

## Sincronización offline (resumen)

Entidades que el agrónomo crea/edita en campo (`Task`, `Observation`, `CostEntry`) llevan
`clientId`, `updatedAt` y viajan por un outbox. El endpoint `POST /sync` aplica los cambios
(last-write-wins, autoridad del servidor) y devuelve el delta desde el último `syncToken`.
Ver ADR correspondiente en `adr/`.
