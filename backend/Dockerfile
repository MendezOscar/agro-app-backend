# --- build ---
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restaura primero (cachea capas de NuGet)
COPY AgroApp.sln .
COPY src/AgroApp.Api/AgroApp.Api.csproj src/AgroApp.Api/
COPY src/AgroApp.Application/AgroApp.Application.csproj src/AgroApp.Application/
COPY src/AgroApp.Domain/AgroApp.Domain.csproj src/AgroApp.Domain/
COPY src/AgroApp.Infrastructure/AgroApp.Infrastructure.csproj src/AgroApp.Infrastructure/
RUN dotnet restore src/AgroApp.Api/AgroApp.Api.csproj

# Copia el resto y publica
COPY . .
RUN dotnet publish src/AgroApp.Api/AgroApp.Api.csproj -c Release -o /app/publish

# --- runtime ---
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# Render inyecta PORT en runtime; Kestrel debe escuchar ahí (shell-form para expandir $PORT).
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "ASPNETCORE_URLS=http://+:${PORT:-8080} dotnet AgroApp.Api.dll"]
