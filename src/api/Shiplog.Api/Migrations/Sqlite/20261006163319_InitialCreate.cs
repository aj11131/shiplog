using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Shiplog.Api.Migrations.Sqlite
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "LogEntries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    Author = table.Column<string>(type: "TEXT", maxLength: 60, nullable: false),
                    Message = table.Column<string>(type: "TEXT", maxLength: 280, nullable: false),
                    CreatedAtUtc = table.Column<DateTime>(type: "TEXT", nullable: false),
                    Cloud = table.Column<string>(type: "TEXT", maxLength: 20, nullable: false),
                    Region = table.Column<string>(type: "TEXT", maxLength: 40, nullable: false),
                    Cluster = table.Column<string>(type: "TEXT", maxLength: 60, nullable: false),
                    Node = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    Pod = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LogEntries", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_LogEntries_CreatedAtUtc",
                table: "LogEntries",
                column: "CreatedAtUtc");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "LogEntries");
        }
    }
}
