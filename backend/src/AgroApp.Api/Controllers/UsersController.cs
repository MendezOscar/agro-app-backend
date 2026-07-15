using AgroApp.Application.Common;
using AgroApp.Domain;
using AgroApp.Infrastructure.Identity;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api.Controllers;

public record CreateUserRequest(string Email, string FullName, string Password, UserRole Role);
public record UpdateUserRequest(string FullName, UserRole Role);
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

    /// <summary>Edita nombre y rol de un usuario de la organización.</summary>
    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, UpdateUserRequest req)
    {
        if (req.Role == UserRole.Owner)
            return BadRequest(new { message = "No se puede asignar el rol Dueño." });

        var user = await _users.Users.FirstOrDefaultAsync(u => u.Id == id && u.OrganizationId == OrgId);
        if (user is null) return NotFound();
        if (user.Role == UserRole.Owner)
            return BadRequest(new { message = "No se puede modificar al Dueño." });

        var oldRole = user.Role;
        user.FullName = req.FullName;
        user.Role = req.Role;
        var result = await _users.UpdateAsync(user);
        if (!result.Succeeded)
            return BadRequest(new { errors = result.Errors.Select(e => e.Description) });

        if (oldRole != req.Role)
        {
            await _users.RemoveFromRoleAsync(user, oldRole.ToString());
            await _users.AddToRoleAsync(user, req.Role.ToString());
        }
        return NoContent();
    }

    /// <summary>Elimina un usuario de la organización (no al Dueño ni a sí mismo).</summary>
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (id == Me.UserId)
            return BadRequest(new { message = "No puedes eliminar tu propia cuenta." });

        var user = await _users.Users.FirstOrDefaultAsync(u => u.Id == id && u.OrganizationId == OrgId);
        if (user is null) return NotFound();
        if (user.Role == UserRole.Owner)
            return BadRequest(new { message = "No se puede eliminar al Dueño." });

        var result = await _users.DeleteAsync(user);
        if (!result.Succeeded)
            return BadRequest(new { errors = result.Errors.Select(e => e.Description) });
        return NoContent();
    }
}
