using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AgroApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddPhenologyRecord : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PhenologyRecords",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CropCycleId = table.Column<Guid>(type: "uuid", nullable: false),
                    RecordedAt = table.Column<DateOnly>(type: "date", nullable: false),
                    Stage = table.Column<int>(type: "integer", nullable: false),
                    PlantHeightCm = table.Column<double>(type: "double precision", nullable: true),
                    PestIncidencePct = table.Column<double>(type: "double precision", nullable: true),
                    DiseaseIncidencePct = table.Column<double>(type: "double precision", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PhenologyRecords", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PhenologyRecords_CropCycleId",
                table: "PhenologyRecords",
                column: "CropCycleId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PhenologyRecords");
        }
    }
}
