using AgroApp.Domain;
using AgroApp.Infrastructure.Identity;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace AgroApp.Infrastructure.Persistence;

public class AppDbContext : IdentityDbContext<ApplicationUser, IdentityRole<Guid>, Guid>
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Organization> Organizations => Set<Organization>();
    public DbSet<Farm> Farms => Set<Farm>();
    public DbSet<Plot> Plots => Set<Plot>();
    public DbSet<CropCycle> CropCycles => Set<CropCycle>();
    public DbSet<Stage> Stages => Set<Stage>();
    public DbSet<WorkTask> WorkTasks => Set<WorkTask>();
    public DbSet<Input> Inputs => Set<Input>();
    public DbSet<CostEntry> CostEntries => Set<CostEntry>();
    public DbSet<Analysis> Analyses => Set<Analysis>();
    public DbSet<Observation> Observations => Set<Observation>();
    public DbSet<ImageAnalysis> ImageAnalyses => Set<ImageAnalysis>();
    public DbSet<HarvestResult> HarvestResults => Set<HarvestResult>();
    public DbSet<PhenologyRecord> PhenologyRecords => Set<PhenologyRecord>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        base.OnModelCreating(b);

        b.Entity<Organization>().HasIndex(x => x.Name);

        b.Entity<Farm>(e =>
        {
            e.HasIndex(x => x.OrganizationId);
            e.HasMany(x => x.Plots).WithOne(x => x.Farm!)
                .HasForeignKey(x => x.FarmId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Plot>(e =>
        {
            e.HasIndex(x => x.FarmId);
            e.HasMany(x => x.CropCycles).WithOne(x => x.Plot!)
                .HasForeignKey(x => x.PlotId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<CropCycle>(e =>
        {
            e.HasIndex(x => x.PlotId);
            e.HasMany(x => x.Stages).WithOne().HasForeignKey(x => x.CropCycleId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Costs).WithOne().HasForeignKey(x => x.CropCycleId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Observations).WithOne().HasForeignKey(x => x.CropCycleId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.HarvestResult).WithOne().HasForeignKey<HarvestResult>(x => x.CropCycleId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Stage>(e =>
        {
            e.HasIndex(x => x.CropCycleId);
            e.HasMany(x => x.Tasks).WithOne().HasForeignKey(x => x.StageId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Observation>(e =>
        {
            e.HasIndex(x => x.CropCycleId);
            e.HasOne(x => x.ImageAnalysis).WithOne()
                .HasForeignKey<ImageAnalysis>(x => x.ObservationId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Input>().HasIndex(x => x.OrganizationId);
        b.Entity<CostEntry>().HasIndex(x => x.CropCycleId);
        b.Entity<Analysis>().HasIndex(x => x.PlotId);
        b.Entity<PhenologyRecord>().HasIndex(x => x.CropCycleId);

        b.Entity<Input>().Property(x => x.UnitCost).HasColumnType("numeric(14,2)");
        b.Entity<CostEntry>().Property(x => x.UnitCost).HasColumnType("numeric(14,2)");
        b.Entity<CostEntry>().Property(x => x.Quantity).HasColumnType("numeric(14,3)");
        b.Entity<CostEntry>().Property(x => x.Total).HasColumnType("numeric(14,2)");
        b.Entity<HarvestResult>().Property(x => x.TotalCost).HasColumnType("numeric(14,2)");
        b.Entity<HarvestResult>().Property(x => x.RevenueEst).HasColumnType("numeric(14,2)");

        b.Entity<RefreshToken>(e =>
        {
            e.HasIndex(x => x.Token);
            e.HasOne<ApplicationUser>().WithMany(u => u.RefreshTokens)
                .HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });
    }
}
