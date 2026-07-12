import { defineStore } from 'pinia'
import { api } from '../api/client'

interface AuthState {
  userId: string | null
  orgId: string | null
  role: string | null
  fullName: string | null
}

export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    userId: localStorage.getItem('user_id'),
    orgId: localStorage.getItem('org_id'),
    role: localStorage.getItem('role'),
    fullName: localStorage.getItem('full_name'),
  }),
  getters: {
    isAuthenticated: (s) => !!s.userId,
    canManageUsers: (s) => s.role === 'Owner' || s.role === 'AgronomistManager',
  },
  actions: {
    async login(email: string, password: string) {
      const res = await api.post('/api/auth/login', { email, password })
      this.persist(res.data)
    },
    persist(data: Record<string, string>) {
      localStorage.setItem('access_token', data.accessToken)
      localStorage.setItem('refresh_token', data.refreshToken)
      localStorage.setItem('user_id', data.userId)
      localStorage.setItem('org_id', data.organizationId)
      localStorage.setItem('role', data.role)
      localStorage.setItem('full_name', data.fullName)
      this.userId = data.userId
      this.orgId = data.organizationId
      this.role = data.role
      this.fullName = data.fullName
    },
    logout() {
      localStorage.clear()
      this.userId = this.orgId = this.role = this.fullName = null
    },
  },
})
