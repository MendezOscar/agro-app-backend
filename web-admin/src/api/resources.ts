import { api } from './client'

export interface Farm {
  id: string
  name: string
  location: number[] | null
  boundary: number[][] | null
  areaHa: number
}
export interface Plot {
  id: string
  farmId: string
  name: string
  boundary: number[][] | null
  areaHa: number
  soilType: string | null
}
export interface Cycle {
  id: string
  plotId: string
  crop: string
  variety: string | null
  status: number
  yieldKg: number | null
  stages?: Stage[]
}
export interface Stage {
  id: string
  kind: number
  status: number
  notes: string | null
}
export interface CostSummary {
  total: number
  byKind: { kind: number; total: number }[]
}
export interface Phenology {
  id: string
  cropCycleId: string
  recordedAt: string
  stage: number
  plantHeightCm: number | null
  pestIncidencePct: number | null
  diseaseIncidencePct: number | null
  notes: string | null
}
export interface ImageAnalysis {
  severity: string
  confidence: number
  diagnosis: string
  recommendations: string
  analyzedAt: string
}
export interface Observation {
  id: string
  cropCycleId: string
  note: string | null
  photoUrl: string | null
  createdAt: string
  analysis: ImageAnalysis | null
}
export interface SoilLayer { depthLabel: string; tempC: number | null; moisturePct: number | null }
export interface WaterBalance {
  et0Mm7d: number; precipMm7d: number; deficitMm: number; irrigationSuggested: boolean; suggestedMm: number
}
export interface GddResult { baseTempC: number; accumulated: number; days: number }
export interface DiseaseRisk { level: string; reason: string }
export interface AgronomyResult {
  soil: SoilLayer[]
  water: WaterBalance | null
  gdd: GddResult | null
  disease: DiseaseRisk | null
  source: string
  message: string | null
}
export interface CycleReport {
  id: string
  crop: string
  variety: string | null
  status: number
  plotName: string | null
  areaHa: number
  yieldKg: number
  yieldPerHa: number
  quality: string | null
  postHarvestLossKg: number
  lossPct: number
  totalCost: number
  revenueEst: number
  margin: number
  costPerKg: number
  costByKind: { kind: number; total: number }[]
  costByStage: { kind: number | null; total: number }[]
}
export interface Cost {
  id: string
  kind: number
  description: string | null
  inputId: string | null
  workTaskId: string | null
  stageId: string | null
  quantity: number
  unitCost: number
  total: number
  incurredAt: string
}
export interface WorkTask {
  id: string
  stageId: string
  title: string
  description: string | null
  assignedToUserId: string | null
  status: number
  dueDate: string | null
  completedAt: string | null
}
export interface OrgUser {
  id: string
  email: string
  fullName: string
  role: number
}
export interface Input {
  id: string
  name: string
  kind: number
  unit: string
  unitCost: number
  stockQty: number
  minStock: number
}
export interface Analysis {
  id: string
  plotId: string
  kind: number
  ph: number | null
  n: number | null
  p: number | null
  k: number | null
  organicMatter: number | null
  texture: string | null
  sampledAt: string | null
}

export const farmsApi = {
  list: () => api.get<Farm[]>('/api/farms').then((r) => r.data),
  create: (body: Partial<Farm>) => api.post<Farm>('/api/farms', body).then((r) => r.data),
  update: (id: string, body: Partial<Farm>) =>
    api.put<Farm>(`/api/farms/${id}`, body).then((r) => r.data),
  remove: (id: string) => api.delete(`/api/farms/${id}`).then((r) => r.data),
  plots: (farmId: string) => api.get<Plot[]>(`/api/farms/${farmId}/plots`).then((r) => r.data),
  createPlot: (farmId: string, body: Partial<Plot>) =>
    api.post<Plot>(`/api/farms/${farmId}/plots`, body).then((r) => r.data),
  updatePlot: (id: string, body: Partial<Plot>) =>
    api.put<Plot>(`/api/plots/${id}`, body).then((r) => r.data),
  removePlot: (id: string) => api.delete(`/api/plots/${id}`).then((r) => r.data),
}

export const cyclesApi = {
  byPlot: (plotId: string) => api.get<Cycle[]>(`/api/plots/${plotId}/cycles`).then((r) => r.data),
  get: (id: string) => api.get<Cycle>(`/api/cycles/${id}`).then((r) => r.data),
  create: (body: { plotId: string; crop: string; variety?: string }) =>
    api.post<Cycle>('/api/cycles', body).then((r) => r.data),
  costSummary: (id: string) =>
    api.get<CostSummary>(`/api/cycles/${id}/costs/summary`).then((r) => r.data),
  costs: (id: string) => api.get<Cost[]>(`/api/cycles/${id}/costs`).then((r) => r.data),
  report: (id: string) => api.get<CycleReport>(`/api/cycles/${id}/report`).then((r) => r.data),
  advanceStage: (stageId: string, body: { status: number; notes?: string | null }) =>
    api.put(`/api/stages/${stageId}`, body).then((r) => r.data),
  phenology: (id: string) => api.get<Phenology[]>(`/api/cycles/${id}/phenology`).then((r) => r.data),
  observations: (id: string) => api.get<Observation[]>(`/api/cycles/${id}/observations`).then((r) => r.data),
  agronomy: (id: string) => api.get<AgronomyResult>(`/api/cycles/${id}/agronomy`).then((r) => r.data),
  addPhenology: (id: string, body: {
    recordedAt: string; stage: number; plantHeightCm?: number | null
    pestIncidencePct?: number | null; diseaseIncidencePct?: number | null; notes?: string | null
  }) => api.post<Phenology>(`/api/cycles/${id}/phenology`, body).then((r) => r.data),
  removePhenology: (recId: string) => api.delete(`/api/phenology/${recId}`).then((r) => r.data),
  addCost: (id: string, body: {
    kind: number; description?: string | null; inputId?: string | null
    workTaskId?: string | null; stageId?: string | null; quantity: number; unitCost: number
  }) => api.post<Cost>(`/api/cycles/${id}/costs`, body).then((r) => r.data),
  removeCost: (costId: string) => api.delete(`/api/costs/${costId}`).then((r) => r.data),
  close: (id: string, body: Record<string, unknown>) =>
    api.post(`/api/cycles/${id}/close`, body).then((r) => r.data),
}

export const tasksApi = {
  byStage: (stageId: string) => api.get<WorkTask[]>(`/api/stages/${stageId}/tasks`).then((r) => r.data),
  create: (stageId: string, body: {
    title: string; description?: string | null; assignedToUserId?: string | null; dueDate?: string | null
  }) => api.post<WorkTask>(`/api/stages/${stageId}/tasks`, body).then((r) => r.data),
  setStatus: (taskId: string, status: number) =>
    api.post<WorkTask>(`/api/tasks/${taskId}/status/${status}`, {}).then((r) => r.data),
  remove: (taskId: string) => api.delete(`/api/tasks/${taskId}`).then((r) => r.data),
}

export const usersApi = {
  list: () => api.get<OrgUser[]>('/api/users').then((r) => r.data),
  create: (body: { email: string; fullName: string; password: string; role: number }) =>
    api.post<OrgUser>('/api/users', body).then((r) => r.data),
  update: (id: string, body: { fullName: string; role: number }) =>
    api.put(`/api/users/${id}`, body).then((r) => r.data),
  remove: (id: string) => api.delete(`/api/users/${id}`).then((r) => r.data),
}

export interface DashboardFarm { id: string; name: string; lat: number | null; lng: number | null; areaHa: number }
export interface DashboardStage { kind: number; status: number }
export interface DashboardCycle { id: string; plotId: string; crop: string; variety: string | null; stages: DashboardStage[]; totalCost: number }
export interface DashboardTask { id: string; title: string; dueDate: string | null; crop: string; overdue: boolean }
export interface CostSlice { kind: number; total: number }
export interface DashboardAlert { level: string; message: string }
export interface Dashboard {
  farms: number; plots: number; activeCycles: number; plannedCycles: number; closedCycles: number
  pendingTasks: number; overdueTasks: number; totalCost: number
  farmsList: DashboardFarm[]; activeCyclesList: DashboardCycle[]
  upcomingTasks: DashboardTask[]; costByKind: CostSlice[]; alerts: DashboardAlert[]
}
export const dashboardApi = {
  get: () => api.get<Dashboard>('/api/dashboard').then((r) => r.data),
}

export const inputsApi = {
  list: () => api.get<Input[]>('/api/inputs').then((r) => r.data),
  create: (body: Omit<Input, 'id'>) => api.post<Input>('/api/inputs', body).then((r) => r.data),
  update: (id: string, body: Omit<Input, 'id'>) =>
    api.put<Input>(`/api/inputs/${id}`, body).then((r) => r.data),
  restock: (id: string, quantity: number) =>
    api.post<Input>(`/api/inputs/${id}/restock`, { quantity }).then((r) => r.data),
  remove: (id: string) => api.delete(`/api/inputs/${id}`).then((r) => r.data),
}

export const analysisApi = {
  byPlot: (plotId: string) =>
    api.get<Analysis[]>(`/api/plots/${plotId}/analyses`).then((r) => r.data),
  create: (plotId: string, body: Omit<Analysis, 'id' | 'plotId'>) =>
    api.post<Analysis>(`/api/plots/${plotId}/analyses`, body).then((r) => r.data),
  remove: (id: string) => api.delete(`/api/analyses/${id}`).then((r) => r.data),
}
