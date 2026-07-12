using AgroApp.Application.Common;
using AgroApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using NetTopologySuite.Geometries;

namespace AgroApp.Infrastructure.Services;

public class SpatialService : ISpatialService
{
    private readonly AppDbContext _db;

    public SpatialService(AppDbContext db) => _db = db;

    public async Task<double> PolygonAreaHectaresAsync(Polygon polygon, CancellationToken ct = default)
    {
        // ST_Area sobre geography devuelve m²; /10000 -> hectáreas. Cálculo geodésico (SRID 4326).
        var wkt = polygon.AsText();
        var result = await _db.Database
            .SqlQueryRaw<double>(
                "SELECT ST_Area(ST_GeomFromText({0}, 4326)::geography) / 10000.0 AS \"Value\"", wkt)
            .ToListAsync(ct);
        return result.FirstOrDefault();
    }
}
