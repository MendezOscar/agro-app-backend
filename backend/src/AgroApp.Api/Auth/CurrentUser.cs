using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using AgroApp.Application.Common;

namespace AgroApp.Api.Auth;

/// <summary>Lee el usuario autenticado desde los claims del JWT del request actual.</summary>
public class CurrentUser : ICurrentUser
{
    private readonly ClaimsPrincipal? _principal;

    public CurrentUser(IHttpContextAccessor accessor) => _principal = accessor.HttpContext?.User;

    public bool IsAuthenticated => _principal?.Identity?.IsAuthenticated ?? false;

    public Guid? UserId =>
        TryGuid(_principal?.FindFirstValue(JwtRegisteredClaimNames.Sub)
                ?? _principal?.FindFirstValue(ClaimTypes.NameIdentifier));

    public Guid? OrganizationId => TryGuid(_principal?.FindFirstValue("org"));

    public string? Role => _principal?.FindFirstValue(ClaimTypes.Role);

    private static Guid? TryGuid(string? value) =>
        Guid.TryParse(value, out var g) ? g : null;
}
