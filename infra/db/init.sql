-- Habilita PostGIS para geometrías de fincas y lotes.
-- La imagen postgis/postgis ya trae la extensión disponible; solo la creamos.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
