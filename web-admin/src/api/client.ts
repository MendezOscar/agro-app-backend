import axios, { type AxiosInstance } from 'axios'

const baseURL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:5192'

export const api: AxiosInstance = axios.create({ baseURL })

// Inyecta el JWT en cada request.
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('access_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

// Refresh automático ante 401 (una vez).
let refreshing: Promise<boolean> | null = null

api.interceptors.response.use(
  (res) => res,
  async (error) => {
    const original = error.config
    if (error.response?.status === 401 && !original._retry) {
      original._retry = true
      refreshing ??= tryRefresh()
      const ok = await refreshing
      refreshing = null
      if (ok) {
        original.headers.Authorization = `Bearer ${localStorage.getItem('access_token')}`
        return api(original)
      }
    }
    return Promise.reject(error)
  },
)

async function tryRefresh(): Promise<boolean> {
  const refresh = localStorage.getItem('refresh_token')
  if (!refresh) return false
  try {
    const res = await axios.post(`${baseURL}/api/auth/refresh`, { refreshToken: refresh })
    localStorage.setItem('access_token', res.data.accessToken)
    localStorage.setItem('refresh_token', res.data.refreshToken)
    return true
  } catch {
    localStorage.clear()
    return false
  }
}
