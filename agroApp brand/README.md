# AgroApp · Manual de marca (mini)

Concepto seleccionado: **Sello** — insignia circular con horizonte, brote y gota.

## Estructura del paquete

```
AgroApp Brand/
├── svg/                          ← formato preferido, escalable, editable
│   ├── mark-color.svg            ← marca principal (con fondo crema)
│   ├── mark-color-transparent.svg← marca principal (fondo transparente)
│   ├── mark-mono-dark.svg        ← versión 1 tinta (sobre claros)
│   ├── mark-mono-light.svg       ← versión 1 tinta blanca (sobre oscuros)
│   ├── logo-horizontal.svg       ← marca + wordmark, lado a lado
│   ├── logo-stacked.svg          ← marca arriba, wordmark abajo, con tagline
│   ├── appicon.svg               ← ícono de aplicación 1024px
│   └── favicon.svg               ← favicon simplificado
└── png/                          ← bitmaps listos para usar
    ├── appicon-{1024,512,256,192,180,152,128,64}.png
    ├── favicon-{16,32,48,64}.png
    ├── mark-color-{256,512,1024}.png
    └── mark-on-white-{512,1024}.png
```

## Paleta

| Token       | Hex       | Uso                                   |
|-------------|-----------|---------------------------------------|
| leaf        | `#2f7a3a` | verde primario (hojas, tallo, acento) |
| leaf-dark   | `#1f5a2a` | borde del sello, contornos serios     |
| leaf-light  | `#62b15a` | acento alternativo                    |
| drop        | `#2c89c9` | azul agua, gota                       |
| drop-light  | `#7cc4ea` | acento en app icon (gota interna)     |
| ink         | `#1a1f1a` | texto principal "Agro"                |
| paper       | `#f7f5f0` | fondo cálido del sello                |

## Tipografía

**Manrope** (Google Fonts) — geométrica, redondeada, alta legibilidad.

- "Agro" → Manrope 800, color **ink** (`#1a1f1a`)
- "App"  → Manrope 800, color **leaf-dark** (`#1f5a2a`)
- letter-spacing: `-0.035em` (compacta el wordmark)

## Tamaños mínimos

- Marca aislada: **24 px** en digital, **15 mm** en impreso.
- App icon: optimizado a 1024 px; reescala limpia a 64.
- Favicon: usar `favicon.svg` o el PNG 32/16 (versión simplificada — la marca completa pierde detalle bajo 24 px).

## Uso del logo en la app

### HTML

```html
<!-- favicon -->
<link rel="icon" href="/AgroApp Brand/svg/favicon.svg" type="image/svg+xml" />
<link rel="apple-touch-icon" href="/AgroApp Brand/png/appicon-180.png" />

<!-- logo en el header -->
<img src="/AgroApp Brand/svg/logo-horizontal.svg" alt="AgroApp" height="40" />
```

### iOS / Android

- iOS: usa `appicon-1024.png` como master en App Store Connect.
- Android: usa `appicon-512.png` para Play Store; `appicon-192.png` para el manifest web.

## Qué evitar

- No rotes la marca.
- No cambies los colores fuera de la paleta.
- No estires el wordmark en horizontal/vertical.
- No coloques el sello sobre fondos con mucho ruido — usa la versión monocromática invertida.
- No combines "Agro" y "App" en un solo color (la diferenciación tipográfica es parte del sistema).
