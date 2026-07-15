using AgroApp.Api.Contracts;
using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Identity;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly UserManager<ApplicationUser> _users;
    private readonly AppDbContext _db;
    private readonly IJwtTokenService _jwt;

    public AuthController(UserManager<ApplicationUser> users, AppDbContext db, IJwtTokenService jwt)
    {
        _users = users;
        _db = db;
        _jwt = jwt;
    }

    /// <summary>Crea una organización nueva y su usuario Owner.</summary>
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest req)
    {
        if (await _users.FindByEmailAsync(req.Email) is not null)
            return Conflict(new { message = "El email ya está registrado." });

        var org = new Organization { Name = req.OrgName };
        _db.Organizations.Add(org);
        await _db.SaveChangesAsync();

        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            UserName = req.Email,
            Email = req.Email,
            FullName = req.FullName,
            OrganizationId = org.Id,
            Role = UserRole.Owner
        };
        var result = await _users.CreateAsync(user, req.Password);
        if (!result.Succeeded)
            return BadRequest(new { errors = result.Errors.Select(e => e.Description) });

        return await IssueTokens(user);
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest req)
    {
        var user = await _users.FindByEmailAsync(req.Email);
        if (user is null || !await _users.CheckPasswordAsync(user, req.Password))
            return Unauthorized(new { message = "Credenciales inválidas." });

        return await IssueTokens(user);
    }

    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> Refresh(RefreshRequest req)
    {
        var stored = await _db.RefreshTokens
            .FirstOrDefaultAsync(t => t.Token == req.RefreshToken);
        if (stored is null || !stored.IsActive)
            return Unauthorized(new { message = "Refresh token inválido o expirado." });

        var user = await _users.FindByIdAsync(stored.UserId.ToString());
        if (user is null) return Unauthorized();

        stored.RevokedAt = DateTimeOffset.UtcNow;      // rotación de refresh token
        return await IssueTokens(user);
    }

    private async Task<ActionResult<AuthResponse>> IssueTokens(ApplicationUser user)
    {
        var pair = _jwt.CreateTokens(user.Id, user.OrganizationId, user.Role.ToString(), user.Email!);

        _db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            Token = pair.RefreshToken,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(30)
        });
        await _db.SaveChangesAsync();

        return Ok(new AuthResponse(
            pair.AccessToken, pair.RefreshToken, pair.AccessExpiresAt,
            user.Id, user.OrganizationId, user.Role.ToString(), user.FullName, user.Email!));
    }

    /// <summary>Cambia la contraseña del usuario autenticado.</summary>
    [Microsoft.AspNetCore.Authorization.Authorize]
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest req)
    {
        var id = User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value
                 ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (id is null) return Unauthorized();
        var user = await _users.FindByIdAsync(id);
        if (user is null) return Unauthorized();

        var result = await _users.ChangePasswordAsync(user, req.CurrentPassword, req.NewPassword);
        if (!result.Succeeded)
            return BadRequest(new { errors = result.Errors.Select(e => e.Description) });
        return NoContent();
    }
}
