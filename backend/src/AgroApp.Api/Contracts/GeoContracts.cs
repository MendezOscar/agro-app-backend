using NetTopologySuite.Geometries;

namespace AgroApp.Api.Contracts;

// Coordenadas en formato [lng, lat] (orden GeoJSON).
public record FarmRequest(string Name, double[]? Location, double[][]? Boundary);
public record FarmResponse(
    Guid Id, string Name, double[]? Location, double[][]? Boundary, double AreaHa, DateTimeOffset CreatedAt);

public record PlotRequest(string Name, double[][]? Boundary, string? SoilType);
public record PlotResponse(
    Guid Id, Guid FarmId, string Name, double[][]? Boundary, double AreaHa, string? SoilType);

/// <summary>Conversión entre coordenadas [lng,lat] del API y geometrías NetTopologySuite (SRID 4326).</summary>
public static class Geo
{
    private static readonly GeometryFactory Factory =
        NetTopologySuite.NtsGeometryServices.Instance.CreateGeometryFactory(srid: 4326);

    public static Point? ToPoint(double[]? c) =>
        c is { Length: 2 } ? Factory.CreatePoint(new Coordinate(c[0], c[1])) : null;

    public static Polygon? ToPolygon(double[][]? ring)
    {
        if (ring is null || ring.Length < 3) return null;
        var coords = ring.Select(p => new Coordinate(p[0], p[1])).ToList();
        if (!coords[0].Equals2D(coords[^1])) coords.Add(coords[0].Copy()); // cerrar anillo
        return Factory.CreatePolygon(coords.ToArray());
    }

    public static double[]? FromPoint(Point? p) => p is null ? null : new[] { p.X, p.Y };

    public static double[][]? FromPolygon(Polygon? poly) =>
        poly is null ? null : poly.ExteriorRing.Coordinates.Select(c => new[] { c.X, c.Y }).ToArray();
}
