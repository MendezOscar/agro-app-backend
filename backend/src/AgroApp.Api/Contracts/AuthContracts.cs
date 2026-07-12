namespace AgroApp.Api.Contracts;

public record RegisterRequest(string OrgName, string FullName, string Email, string Password);
public record LoginRequest(string Email, string Password);
public record RefreshRequest(string RefreshToken);

public record AuthResponse(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset AccessExpiresAt,
    Guid UserId,
    Guid OrganizationId,
    string Role,
    string FullName);
