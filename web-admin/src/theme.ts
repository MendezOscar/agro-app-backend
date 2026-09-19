import { definePreset } from '@primevue/themes'
import Aura from '@primevue/themes/aura'

/**
 * Tema de AgroApp sobre Aura: verde de marca como color primario y una escala
 * de superficies con un punto de verde para que las tarjetas no se vean grises.
 */
export const AgroPreset = definePreset(Aura, {
  primitive: {
    borderRadius: { none: '0', xs: '4px', sm: '7px', md: '10px', lg: '14px', xl: '20px' },
  },
  semantic: {
    primary: {
      50: '#f1f8f2',
      100: '#ddedde',
      200: '#bcdcbf',
      300: '#8fc494',
      400: '#5da865',
      500: '#2f7a3a',
      600: '#28692f',
      700: '#215628',
      800: '#1a4520',
      900: '#133217',
      950: '#0b1f0e',
    },
    focusRing: { width: '3px', style: 'solid', color: '{primary.200}', offset: '0' },
    formField: {
      paddingX: '0.7rem',
      paddingY: '0.55rem',
      borderRadius: '{border.radius.md}',
    },
    colorScheme: {
      light: {
        surface: {
          0: '#ffffff',
          50: '#f7f9f6',
          100: '#eef1ec',
          200: '#e2e7df',
          300: '#cdd5c9',
          400: '#a6b0a2',
          500: '#7d887a',
          600: '#5c655a',
          700: '#454d43',
          800: '#2c332b',
          900: '#1a1f1a',
          950: '#0f130f',
        },
        primary: {
          color: '{primary.500}',
          contrastColor: '#ffffff',
          hoverColor: '{primary.600}',
          activeColor: '{primary.700}',
        },
        content: { background: '{surface.0}', borderColor: '{surface.200}' },
        text: { color: '{surface.900}', mutedColor: '{surface.600}' },
      },
    },
  },
  components: {
    card: {
      root: { background: '{surface.0}', borderRadius: '{border.radius.lg}', shadow: '0 1px 2px rgba(20,40,20,.05)' },
      body: { padding: '1.15rem' },
      title: { fontSize: '1rem', fontWeight: '700' },
    },
    button: { root: { borderRadius: '{border.radius.md}', label: { fontWeight: '600' } } },
    datatable: {
      headerCell: { background: '{surface.50}', color: '{surface.600}', fontWeight: '600' },
      bodyCell: { borderColor: '{surface.100}' },
    },
    tag: { root: { fontWeight: '600', borderRadius: '999px' } },
  },
})
