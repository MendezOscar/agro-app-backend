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
export interface OrgUser {
  id: string
  email: string
  fullName: string
  role: number
}

export const farmsApi = {
  list: () => api.get<Farm[]>('/api/farms').then((r) => r.data),
  create: (body: Partial<Farm>) => api.post<Farm>('/api/farms', body).then((r) => r.data),
  plots: (farmId: string) => api.get<Plot[]>(`/api/farms/${farmId}/plots`).then((r) => r.data),
  createPlot: (farmId: string, body: Partial<Plot>) =>
    api.post<Plot>(`/api/farms/${farmId}/plots`, body).then((r) => r.data),
}

export const cyclesApi = {
  byPlot: (plotId: string) => api.get<Cycle[]>(`/api/plots/${plotId}/cycles`).then((r) => r.data),
  get: (id: string) => api.get<Cycle>(`/api/cycles/${id}`).then((r) => r.data),
  create: (body: { plotId: string; crop: string; variety?: string }) =>
    api.post<Cycle>('/api/cycles', body).then((r) => r.data),
  costSummary: (id: string) =>
    api.get<CostSummary>(`/api/cycles/${id}/costs/summary`).then((r) => r.data),
  close: (id: string, body: Record<string, unknown>) =>
    api.post(`/api/cycles/${id}/close`, body).then((r) => r.data),
}

export const usersApi = {
  list: () => api.get<OrgUser[]>('/api/users').then((r) => r.data),
  create: (body: { email: string; fullName: string; password: string; role: number }) =>
    api.post<OrgUser>('/api/users', body).then((r) => r.data),
}
