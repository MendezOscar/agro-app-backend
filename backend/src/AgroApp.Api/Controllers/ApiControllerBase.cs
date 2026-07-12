using AgroApp.Application.Common;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AgroApp.Api.Controllers;

[ApiController]
[Authorize]
public abstract class ApiControllerBase : ControllerBase
{
    protected ICurrentUser Me { get; }

    protected ApiControllerBase(ICurrentUser me) => Me = me;

    protected Guid OrgId => Me.OrganizationId ?? throw new UnauthorizedAccessException();
}
