# syntax=docker/dockerfile:1

# ---- build ----
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Restore first, in its own layer, so it is cached until the project file changes.
COPY Shiplog.Api/Shiplog.Api.csproj Shiplog.Api/
RUN dotnet restore Shiplog.Api/Shiplog.Api.csproj

COPY Shiplog.Api/ Shiplog.Api/
ARG VERSION=0.0.0-local
RUN dotnet publish Shiplog.Api/Shiplog.Api.csproj -c Release -o /app --no-restore -p:Version=${VERSION}

# The runtime image has no shell, so create the SQLite data directory here.
RUN mkdir /data

# ---- runtime ----
# "Chiseled" images contain only what .NET needs: no shell or package manager, and they run as a non-root user.
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
WORKDIR /app
COPY --from=build /app .
COPY --from=build --chown=$APP_UID:$APP_UID /data /data

ENV ASPNETCORE_HTTP_PORTS=8080 \
    ConnectionStrings__Shiplog="Data Source=/data/shiplog.db"
EXPOSE 8080
USER $APP_UID

ENTRYPOINT ["dotnet", "Shiplog.Api.dll"]
