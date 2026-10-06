# Step 1 — The app, locally

**Goal:** a small but realistic three-tier app that runs on your machine with no cloud, and that already has the habits Kubernetes will need: health probes, configuration from environment variables, structured logs, telemetry, non-root containers.

## What was built

```
browser ──► web (nginx :8080) ──/api/*──► api (ASP.NET :8080) ──► SQLite file / PostgreSQL
                │                            │
                └── /config.json             └── OTLP ──► Aspire dashboard (local)
                    (runtime settings)                    OTel Collector → Azure Monitor (cloud, step 3)
```

### API ([src/api/Shiplog.Api](../src/api/Shiplog.Api))

| Endpoint | Purpose |
|---|---|
| `GET/POST /api/entries`, `GET/DELETE /api/entries/{id}` | The log itself |
| `GET /api/diagnostics` | Cloud / region / cluster / node / pod / version / DB status |
| `GET /healthz/live` | **Liveness**: is the process OK? Has no dependencies, because restarting a pod won't fix a database outage. |
| `GET /healthz/ready` | **Readiness**: can it serve traffic? Includes a DB check, so a failing pod is taken out of the Service instead of restarted. |

Things worth reading in the code:

- **One codebase, two databases.** [ShiplogDbContext.cs](../src/api/Shiplog.Api/Data/ShiplogDbContext.cs) has an abstract context and a subclass per provider, each with its own migrations (`Migrations/Sqlite`, `Migrations/Postgres`). `Database__Provider` picks one at startup.
- **Migrations as a separate step.** `dotnet Shiplog.Api.dll --migrate-only` applies migrations and exits. Locally the API also migrates on startup. In Kubernetes, step 2 runs this as a Helm hook Job, so that three API replicas don't all try to migrate at the same moment.
- **Where am I running?** [RuntimeInfo.cs](../src/api/Shiplog.Api/Diagnostics/RuntimeInfo.cs) binds `Runtime__Cloud`, `Runtime__Node`, etc. from env vars. In Kubernetes the node and pod names come from the *Downward API*. Every response also carries an `X-Served-By: <pod>` header.
- **Telemetry is vendor-neutral.** [TelemetryExtensions.cs](../src/api/Shiplog.Api/Telemetry/TelemetryExtensions.cs) sends OTLP to whatever `OTEL_EXPORTER_OTLP_ENDPOINT` points at. The code doesn't change between the local dashboard and Azure Monitor; only the endpoint does. There's also a custom metric, `shiplog.entries.created`.
- **Logs are JSON in containers** (one object per line, easy for a log collector to parse) and plain text in Development.

### Web ([src/web](../src/web))

- Angular 22: standalone components, signals, zoneless change detection, lazy-loaded routes.
- **Runtime config, not build-time config.** [app-config.ts](../src/web/src/app/core/app-config.ts) fetches `/config.json` before bootstrapping. In the container, nginx generates that JSON from env vars ([default.conf.template](../src/web/nginx/default.conf.template)). The result is **build once, deploy anywhere**: the same image runs locally, on AKS and on EKS.
- **Same-origin API.** nginx proxies `/api/*` to the API, so the browser never makes a cross-origin call and no CORS is needed.
- **Served-by tracking.** [served-by.ts](../src/web/src/app/core/served-by.ts) is an HTTP interceptor that records the pod from every response. The Diagnostics page has a *Send 20 requests* button and a per-pod counter, which is your load-balancing visualizer for step 2.
- **Browser telemetry** with the Application Insights SDK. It's **lazy-loaded** and only downloads when a connection string is configured, which saves about 180 kB on the initial bundle.

### Containers

- API: multi-stage build onto a **chiseled** .NET image: no shell, no package manager, non-root user. That's a much smaller attack surface, but you can't `kubectl exec` into it with a shell. The trade-off is deliberate.
- Web: Node build stage, then **nginx-unprivileged** (non-root, port 8080). Both images listen on 8080 because non-root processes can't bind to ports below 1024.

## Tests

| Suite | Count | What |
|---|---|---|
| xUnit ([Shiplog.Api.Tests](../src/api/Shiplog.Api.Tests)) | 20 | Validator rules; real HTTP calls against the API hosted in memory (`WebApplicationFactory`) with a throwaway SQLite file and a fake clock |
| Vitest ([src/web](../src/web/src/app)) | 20 | Config loading/fallback, interceptor, HTTP service, components (form validation, submit, delete, error states) |

## Try this

1. **Run it without containers** (see README Option A). Open http://localhost:4200, post an entry, then open *Diagnostics*. You'll see a single pod: your machine name.
2. **Read the raw API:** open `src/api/Shiplog.Api/Shiplog.Api.http` in VS Code with the REST Client extension and send the requests. Look at the `X-Served-By` header and the validation problem response.
3. **Break readiness:** with Option B and Postgres, run `docker compose stop db`. `/healthz/live` still returns 200 while `/healthz/ready` fails. In Kubernetes that means "stop sending traffic" rather than "restart me".
4. **Follow a trace:** with Option B, post an entry, then in the Aspire dashboard (http://localhost:18888) open *Traces*. You'll see the `POST /api/entries` span with the database command beneath it. Then check *Structured logs* for "Log entry … created" and *Metrics* for `shiplog.entries.created`.
5. **Change config without rebuilding:** in `compose.yaml` set `SHIPLOG_ENVIRONMENT: hello` on `web`, run `docker compose up -d web`, and refresh. The badge changes with the same image.

## Known gaps (on purpose, for later steps)

- No authentication yet. `author` is typed in by the user; step 4 will take it from the Entra ID token.
- No Content-Security-Policy header yet. Angular's inline critical CSS and the App Insights endpoints need a carefully written CSP, which is a good hardening exercise for later.
- The PostgreSQL migration has been generated but has not yet been run against a real Postgres. Option B with `compose.postgres.yaml` is the first place it runs.
