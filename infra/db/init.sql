-- Bootstrap manual de la base en Neon (ejecutar una vez en el SQL Editor de Neon).
-- La migración Initial de EF también crea postgis, pero dejarlo explícito evita
-- sorpresas si Neon exige habilitar la extensión antes del primer despliegue.
CREATE EXTENSION IF NOT EXISTS postgis;
