using AgroApp.Domain;
using AgroApp.Infrastructure.Identity;
using AgroApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Api;

/// <summary>Aplica migraciones y crea datos demo (solo en desarrollo).</summary>
public static class DbSeeder
{
    public static async Task MigrateAndSeedAsync(IServiceProvider sp)
    {
        var db = sp.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();

        var roleMgr = sp.GetRequiredService<RoleManager<IdentityRole<Guid>>>();
        foreach (var role in Enum.GetNames<UserRole>())
            if (!await roleMgr.RoleExistsAsync(role))
                await roleMgr.CreateAsync(new IdentityRole<Guid>(role));

        if (await db.Organizations.AnyAsync()) return; // ya sembrado

        var org = new Organization { Name = "Finca Demo" };
        db.Organizations.Add(org);
        await db.SaveChangesAsync();

        var users = sp.GetRequiredService<UserManager<ApplicationUser>>();
        var owner = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            UserName = "owner@demo.com",
            Email = "owner@demo.com",
            EmailConfirmed = true,
            FullName = "Dueño Demo",
            OrganizationId = org.Id,
            Role = UserRole.Owner
        };
        await users.CreateAsync(owner, "Demo1234!");
        await users.AddToRoleAsync(owner, UserRole.Owner.ToString());

        // Finca demo con un polígono simple (cuadro ~ en Colombia) y un lote.
        var factory = NetTopologySuite.NtsGeometryServices.Instance.CreateGeometryFactory(4326);
        var ring = new[]
        {
            new NetTopologySuite.Geometries.Coordinate(-75.60, 6.20),
            new NetTopologySuite.Geometries.Coordinate(-75.59, 6.20),
            new NetTopologySuite.Geometries.Coordinate(-75.59, 6.21),
            new NetTopologySuite.Geometries.Coordinate(-75.60, 6.21),
            new NetTopologySuite.Geometries.Coordinate(-75.60, 6.20)
        };
        var farm = new Farm
        {
            OrganizationId = org.Id,
            Name = "Lote Principal",
            Location = factory.CreatePoint(new NetTopologySuite.Geometries.Coordinate(-75.595, 6.205)),
            Boundary = factory.CreatePolygon(ring)
        };
        db.Farms.Add(farm);
        await db.SaveChangesAsync();
    }
}
