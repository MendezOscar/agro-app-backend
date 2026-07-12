using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Identity;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record CreateUserRequest(string Email, string FullName, string Password, UserRole Role);
public record UserResponse(Guid Id, string Email, string FullName, UserRole Role);

/// <summary>Gestión de usuarios dentro de la organización. Solo Owner/Manager.</summary>
[Route("api/users")]
[Authorize(Roles = "Owner,AgronomistManager")]
public class UsersController : ApiControllerBase
{
    private readonly UserManager<ApplicationUser> _users;
    public UsersController(UserManager<ApplicationUser> users, ICurrentUser me) : base(me) => _users = users;

    [HttpGet]
    public async Task<ActionResult<IEnumerable<UserResponse>>> List()
    {
        var list = await _users.Users.Where(u => u.OrganizationId == OrgId)
            .OrderBy(u => u.FullName).ToListAsync();
        return Ok(list.Select(u => new UserResponse(u.Id, u.Email!, u.FullName, u.Role)));
    }

    [HttpPost]
    public async Task<ActionResult<UserResponse>> Create(CreateUserRequest req)
    {
        if (req.Role == UserRole.Owner)
            return BadRequest(new { message = "No se puede crear otro Owner." });
        if (await _users.FindByEmailAsync(req.Email) is not null)
            return Conflict(new { message = "El email ya está registrado." });

        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            UserName = req.Email,
            Email = req.Email,
            EmailConfirmed = true,
            FullName = req.FullName,
            OrganizationId = OrgId,   // hereda la organización del creador
            Role = req.Role
        };
        var result = await _users.CreateAsync(user, req.Password);
        if (!result.Succeeded)
            return BadRequest(new { errors = result.Errors.Select(e => e.Description) });
        await _users.AddToRoleAsync(user, req.Role.ToString());

        return Ok(new UserResponse(user.Id, user.Email!, user.FullName, user.Role));
    }
}
