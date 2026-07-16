using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AgroApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddInputStock : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<double>(
                name: "MinStock",
                table: "Inputs",
                type: "double precision",
                nullable: false,
                defaultValue: 0.0);

            migrationBuilder.AddColumn<double>(
                name: "StockQty",
                table: "Inputs",
                type: "double precision",
                nullable: false,
                defaultValue: 0.0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "MinStock",
                table: "Inputs");

            migrationBuilder.DropColumn(
                name: "StockQty",
                table: "Inputs");
        }
    }
}
