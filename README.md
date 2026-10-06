# ⚓ Shiplog

A deliberately small app for learning and comparing **AWS EKS** and **Azure AKS** with **Terraform**, **Helm** and real **CI/CD**.

Users post short entries to a shared ship's log. Every entry is stamped with the **cloud, cluster, node and pod** that wrote it, and every API response says which pod served it. When you scale, roll out, kill pods or switch clouds, the effect shows up in the app itself.

| Service | Tech | Path |
|---|---|---|
| `shiplog-web` | Angular 22 (zoneless, signals), served by nginx | [src/web](src/web) |
| `shiplog-api` | ASP.NET Core 10 minimal API, EF Core, OpenTelemetry | [src/api](src/api) |
| data store | SQLite locally, PostgreSQL in the cluster | — |

## Roadmap

| Step | What | Status |
|---|---|---|
| 1 | App code, unit tests, Docker Compose, local telemetry | ✅ [notes](docs/01-local-app.md) |
| 2 | Helm chart on a local kind cluster | ✅ [notes](docs/02-helm-kind.md) |
| 3 | Terraform + CI/CD for AKS, Azure observability stack | 🚧 [notes & setup](docs/03-aks-terraform.md) |
| 4 | Entra ID sign-in | ⏳ |
| 5 | Add EKS | ⏳ |
| 6 | Experiments | ⏳ |

## Run it locally

### Option A: no containers (fastest inner loop)

Prerequisites: .NET 10 SDK, Node 24.

```bash
# terminal 1 – API on http://localhost:5253 (SQLite file, migrations applied automatically)
dotnet run --project src/api/Shiplog.Api

# terminal 2 – Angular on http://localhost:4200 (proxies /api to the API)
cd src/web && npm install && npm start
```

### Option B: Docker Compose (what the cluster will run)

Prerequisites: Docker Desktop.

```bash
docker compose up --build
```

- App: http://localhost:8080
- Telemetry (traces, metrics, logs): http://localhost:18888

To use PostgreSQL instead of SQLite:

```bash
docker compose -f compose.yaml -f compose.postgres.yaml up --build
```

### Option C: Kubernetes (kind + Helm)

Prerequisites: Docker Desktop, kind, kubectl, Helm.

```powershell
./scripts/kind-up.ps1     # 3-node cluster, builds images, installs the chart, runs helm test
./scripts/kind-down.ps1   # delete the cluster
```

- App: http://localhost:8090
- Telemetry: http://localhost:18890

## Tests

```bash
dotnet test src/api/Shiplog.slnx      # xUnit: validation + in-memory API tests
cd src/web && npm run test:ci         # Vitest: services, interceptor, components (with coverage)
cd src/web && npm run lint            # angular-eslint
```

CI runs all of this on every pull request. Terraform changes get a plan comment on the PR, and merges are applied and deployed after approval ([docs/03](docs/03-aks-terraform.md)).

App code is built and tested by [app-ci.yml](.github/workflows/app-ci.yml). Chart changes are linted, schema-validated and deployed to a throwaway kind cluster ([chart-ci.yml](.github/workflows/chart-ci.yml)).

## Repository layout

```
src/api/            ASP.NET API + tests (Shiplog.slnx)
src/web/            Angular client + nginx config
compose*.yaml       Local container stack
docs/               Per-step learning notes
.github/workflows/  CI/CD
charts/shiplog/     Helm chart (+ postgres subchart)
deploy/kind/        kind cluster config
deploy/otel-collector/  OpenTelemetry Collector values (Azure Monitor)
scripts/            kind-up.ps1 / kind-down.ps1
infra/bootstrap/    one-time: state storage + GitHub OIDC identities
infra/azure/        observability + aks stacks
infra/modules/      reusable Terraform modules
```
