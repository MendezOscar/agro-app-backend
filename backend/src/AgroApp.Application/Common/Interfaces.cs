using NetTopologySuite.Geometries;

namespace AgroApp.Application.Common;

/// <summary>Usuario autenticado del request actual (resuelto desde el JWT).</summary>
public interface ICurrentUser
{
    Guid? UserId { get; }
    Guid? OrganizationId { get; }
    string? Role { get; }
    bool IsAuthenticated { get; }
}

public record TokenPair(string AccessToken, string RefreshToken, DateTimeOffset AccessExpiresAt);

public interface IJwtTokenService
{
    /// <summary>Genera access token (con claims de usuario/org/rol) y un refresh token opaco.</summary>
    TokenPair CreateTokens(Guid userId, Guid organizationId, string role, string email);
}

/// <summary>Operaciones geoespaciales soportadas por PostGIS.</summary>
public interface ISpatialService
{
    /// <summary>Área en hectáreas de un polígono (cálculo geodésico vía PostGIS geography).</summary>
    Task<double> PolygonAreaHectaresAsync(Polygon polygon, CancellationToken ct = default);
}

/// <summary>Almacenamiento de objetos (fotos de observaciones) en S3/MinIO.</summary>
public interface IStorageService
{
    /// <summary>Sube un objeto y devuelve la clave (key) con la que quedó almacenado.</summary>
    Task<string> UploadAsync(Stream content, string key, string contentType, CancellationToken ct = default);

    /// <summary>URL temporal de lectura para una clave.</summary>
    string GetPresignedUrl(string key, TimeSpan expiry);

    /// <summary>Descarga el objeto como bytes (para enviarlo a la IA).</summary>
    Task<byte[]> DownloadAsync(string key, CancellationToken ct = default);
}

/// <summary>Resultado estructurado del análisis de imagen del cultivo.</summary>
public record ImageAnalysisResult(
    string Diagnosis, string Severity, double Confidence, string Recommendations, string RawJson);

/// <summary>Análisis de imágenes de cultivo con un modelo de visión (Claude).</summary>
public interface IImageAnalyzer
{
    Task<ImageAnalysisResult> AnalyzeAsync(
        byte[] image, string contentType, string cropContext, CancellationToken ct = default);
}

/// <summary>Cola en memoria de observaciones pendientes de análisis por IA.</summary>
public interface IAnalysisQueue
{
    void Enqueue(Guid observationId);
    IAsyncEnumerable<Guid> DequeueAllAsync(CancellationToken ct);
}
