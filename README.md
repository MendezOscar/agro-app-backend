# AgroApp

Plataforma para que dueños de finca y agrónomos gestionen el ciclo completo de una cosecha
(las 8 etapas: planificación → preparación de suelo → siembra → manejo del cultivo →
monitoreo fenológico → cosecha → poscosecha → evaluación), registrando fincas y lotes en
mapa, tareas, costos, insumos, observaciones con fotos y análisis de imágenes con IA.

## Componentes (monorepo)

| Carpeta | Qué es | Stack |
|---|---|---|
| `agroapp/` | App móvil (agrónomo en campo, offline-first) | Flutter, Riverpod, Drift, MapLibre |
| `web-admin/` | Panel del dueño de finca | Vue 3 + Vite + TS, Pinia, MapLibre GL, PrimeVue |
| `backend/` | API REST y lógica de negocio | .NET 8, EF Core + PostGIS, JWT |
| `infra/` | Servicios locales de desarrollo | Docker Compose (PostgreSQL+PostGIS, MinIO) |
| `docs/` | Modelo de dominio y decisiones (ADRs) | Markdown |

> Nota: el backend usa **.NET 8** (LTS) porque es la versión instalada; el plan mencionaba
> .NET 9. Migrar es trivial si se instala el SDK 9.

## Puesta en marcha (dev)

### 1. Infra
```bash
cd infra
cp .env.example .env   # ajusta secretos
docker compose up -d
# Postgres:5433  ·  MinIO API:9000  ·  MinIO consola:9001
```

### 2. Backend
```bash
cd backend
dotnet build
dotnet run --project src/AgroApp.Api   # Swagger en la URL que imprime
```

### 3. Web admin
```bash
cd web-admin
npm install
cp .env.example .env   # ajusta VITE_MAPTILER_KEY para habilitar el mapa
npm run dev            # http://localhost:5173
```
Login demo: `owner@demo.com` / `Demo1234!`.

### 4. App Flutter
```bash
cd agroapp
flutter pub get
dart run build_runner build          # genera database.g.dart (Drift)
# Android emulador (10.0.2.2 = host). iOS simulador: usa http://localhost:5192
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:5192 \
  --dart-define=MAPTILER_KEY=tu_key
```

Notas:
- Sin `MAPTILER_KEY` la app funciona pero la pantalla de mapa muestra un aviso.
- MapLibre no requiere token secreto de compilación (a diferencia de Mapbox); la key de
  MapTiler es solo para los tiles y se obtiene gratis en cloud.maptiler.com (sin tarjeta).
- Login demo: `owner@demo.com` / `Demo1234!`.

## Estado

- [x] **M0** — Andamiaje de monorepo e infra
- [x] **M1** — Backend núcleo + auth + BD (PostGIS)
- [x] **M2** — Ciclo de cosecha end-to-end (API) + sync
- [x] **M3** — App Flutter offline-first
- [x] **M4** — Web admin Vue
- [x] **M5** — IA de imágenes (Claude vision)
