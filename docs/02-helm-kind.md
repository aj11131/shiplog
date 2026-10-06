# Step 2 — Helm chart on a local kind cluster

**Goal:** package Shiplog as a Helm chart and run it on a real (local, free) multi-node Kubernetes cluster, with the security and reliability settings you'd want in the cloud: non-root pods, NetworkPolicies, probes, PodDisruptionBudgets, autoscaling and persistent storage.

## Run it

Prerequisites: Docker Desktop (running), kind, kubectl, Helm.

```powershell
./scripts/kind-up.ps1              # create cluster, build + load images, install chart, run helm test
./scripts/kind-up.ps1 -SkipBuild   # chart-only changes
./scripts/kind-down.ps1            # delete the cluster
```

If PowerShell refuses to run scripts, use `powershell -ExecutionPolicy Bypass -File .\scripts\kind-up.ps1`.

| URL | What |
|---|---|
| http://localhost:8090 | The app (NodePort 30080) |
| http://localhost:18890 | Telemetry dashboard (NodePort 30888) |

These ports differ from Docker Compose (8080/18888), so both can run at the same time.

## What's in the cluster

```
                    kind cluster "shiplog" (Docker containers acting as nodes)
 localhost:8090 ─► ┌─ control-plane ─┐ ┌──── worker ────┐ ┌──── worker2 ───┐
                   │  (no app pods)  │ │ web  api  api   │ │ web  api  pg-0 │
                   └─────────────────┘ └────────────────┘ └──────── dash ──┘
                    NodePort 30080 ─► Service shiplog-web ─► web pods ─► Service shiplog-api ─► api pods ─► shiplog-postgres-0
```

| Resource | Why |
|---|---|
| **Deployment** web ×2, api ×3 (HPA 3–6) | Stateless; `maxUnavailable: 0` rolling updates keep full capacity during a rollout |
| **StatefulSet** postgres ×1 + **PVC** | Stable name (`shiplog-postgres-0`) and its own disk, which survives pod restarts |
| **Headless Service** for postgres | DNS resolves straight to the pod IP; no virtual IP needed for a single stateful pod |
| **Init container** `migrate` | Runs `--migrate-only` before the API container starts |
| **HPA** | Scales the API on CPU (needs metrics-server, which the script installs) |
| **PodDisruptionBudget** | Node drains (upgrades) can't take down every replica at once |
| **NetworkPolicy** ×5 | Default deny, then web ← anyone, api ← web only, postgres ← api only |
| **topologySpreadConstraints** | Prefer spreading replicas across nodes |
| **Pod Security "restricted"** (namespace label) | The API server *rejects* pods that run as root, allow privilege escalation, etc. |
| **helm test** pod | Smoke test through the real path: web → api → postgres |

## Chart layout

```
charts/shiplog/
  Chart.yaml            # declares the postgres subchart dependency (condition: postgres.enabled)
  values.yaml           # defaults, heavily commented
  values-kind.yaml      # kind overrides: local images, NodePorts, HPA on, dev dashboard on
  templates/
    _helpers.tpl        # names, labels, image refs, DB connection string
    api.yaml  web.yaml  dashboard.yaml  networkpolicy.yaml
    tests/smoke-test.yaml
  charts/postgres/      # local subchart: StatefulSet, headless Service, Secret
```

To read the actual YAML Helm generates:

```powershell
helm template shiplog charts/shiplog -f charts/shiplog/values-kind.yaml | Out-File rendered.yaml
```

## Design decisions worth understanding

**Migrations: init container, not a Helm hook Job.** The obvious Helm approach is a `pre-install,pre-upgrade` hook Job, but on the *first* install hooks run before any normal resources exist, so the Job starts before Postgres does. An init container avoids that ordering problem. If Postgres isn't ready yet, the init container fails and Kubernetes retries it with back-off. You'll see `INIT_RESTARTS: 2` on a fresh install; that's expected. EF Core also takes a database lock while migrating, so three replicas starting together don't collide. The cost is that every new pod checks migrations, which takes a few milliseconds when there's nothing to apply.

**Your own Postgres subchart, not Bitnami.** Bitnami's free images stopped being versioned and updated in 2025, so the chart uses the official `postgres:18-alpine` image in a small subchart you can read in full. The `postgres.enabled` condition lets AKS or EKS switch to a managed database (`database.external.*`) without changing any templates.

**The password lifecycle (a classic gotcha).** The Secret's password is generated once, then reused via `lookup` on every upgrade. It's marked `helm.sh/resource-policy: keep` because StatefulSet volumes are **not** deleted by `helm uninstall`. Postgres only reads `POSTGRES_PASSWORD` when it first initializes the data directory, so a reinstall that generated a new password would lock the API out of its own database.

**`$(DB_PASSWORD)` in the connection string.** Kubernetes expands `$(VAR)` in env values from variables defined *earlier in the same list*. The password stays in the Secret and the connection string is assembled at runtime.

**Read-only root filesystems.** Each container gets small `emptyDir` volumes for the paths it really writes: nginx's `conf.d` (its entrypoint renders the template there) and `/tmp`, and Postgres's socket directory. Everything else is immutable.

**`pullPolicy: Never` on kind.** Images come from `kind load docker-image`, not a registry. `Never` makes a missing image fail with a clear `ErrImageNeverPull` instead of a confusing pull from Docker Hub.

**Same tag, new image.** With the tag always `local`, Kubernetes can't tell that the image changed, so `kind-up.ps1` runs `kubectl rollout restart` after rebuilding. In the cloud, every build gets a unique tag (the git SHA), so a `helm upgrade` is enough.

## What was verified

- `helm test`: web → nginx → api → postgres, including a write.
- Requests through the NodePort spread across API pods: 8/7/6 over three pods from the Diagnostics page.
- NetworkPolicies are **enforced** by kind's CNI: a rogue pod in the namespace can reach web but times out on the API and Postgres.
- The HPA reads CPU metrics from metrics-server.
- A `helm upgrade` rolled the API one pod at a time with no downtime.
- Traces from all API pods show up in the in-cluster dashboard.

## Try this

1. **Watch the pods.** In a second terminal: `kubectl get pods -n shiplog -o wide -w`. Keep it open for everything below.
2. **Self-healing.** `kubectl delete pod -n shiplog -l app.kubernetes.io/component=api --wait=false`. New pods appear immediately. Click *Send 20 requests* on the Diagnostics page during the restart; the readiness probes keep traffic away from pods that aren't ready.
3. **Database outage vs. liveness.** `kubectl scale statefulset shiplog-postgres -n shiplog --replicas=0`. API pods go **0/1 Ready** (readiness fails) but are **not restarted** (liveness doesn't check the DB). With no ready API pods, the Service has no endpoints and nginx answers `/api` calls with **504**, so the app shows an error banner. Scale it back to 1 and they recover. Your entries are still there, because the PVC kept the data.
4. **Prove the NetworkPolicy.**
   ```powershell
   kubectl run probe -n shiplog --rm -it --image=curlimages/curl:8.22.0 --overrides='{\"spec\":{\"securityContext\":{\"runAsNonRoot\":true,\"runAsUser\":100,\"seccompProfile\":{\"type\":\"RuntimeDefault\"}}}}' -- sh
   # inside:  curl -m 3 http://shiplog-api:8080/healthz/live   -> times out
   #          curl -m 3 http://shiplog-web/healthz             -> ok
   ```
   Then `kubectl delete networkpolicy -n shiplog --all` and try again (re-run `./scripts/kind-up.ps1 -SkipBuild` to restore them).
5. **Pod Security in action.** `kubectl run root-test -n shiplog --image=nginx`. It's rejected, and the error lists every rule a plain `nginx` pod breaks.
6. **Autoscaling.** Generate load from inside the cluster:
   ```powershell
   kubectl run load -n shiplog --rm -it --image=curlimages/curl:8.22.0 --overrides='{\"spec\":{\"securityContext\":{\"runAsNonRoot\":true,\"runAsUser\":100,\"seccompProfile\":{\"type\":\"RuntimeDefault\"}}}}' -- sh -c 'while true; do curl -s http://shiplog-web/api/entries >/dev/null; done'
   ```
   and `kubectl get hpa -n shiplog -w` in another terminal. Stop the load and the HPA scales back down after about 5 minutes (its default stabilization window).
7. **Drain a node.** `kubectl drain shiplog-worker --ignore-daemonsets --delete-emptydir-data`. The PDBs keep at least one web and one API pod running throughout. Postgres moves only if its volume can follow it; on kind, `local-path` volumes are tied to a node, so watch what happens. Undo it with `kubectl uncordon shiplog-worker`.
8. **Helm history and rollback.** Change `web.replicaCount` with `helm upgrade ... --set web.replicaCount=3`, then run `helm history shiplog -n shiplog` and `helm rollback shiplog 1 -n shiplog`.

## Preview: how this changes on AKS / EKS

| Concern | kind (now) | AKS / EKS (steps 3 & 5) |
|---|---|---|
| Images | `kind load`, tag `local` | ACR / ECR, tag = git SHA, pulled using the cluster's identity |
| Exposure | NodePort + Docker port mapping | Gateway API / Ingress with a cloud load balancer and TLS |
| Storage | `local-path` (node-local) | Azure Disk / EBS CSI drivers (zonal) |
| NetworkPolicy | kindnet | Azure CNI powered by Cilium / VPC CNI network policy |
| Telemetry | in-cluster Aspire dashboard | OpenTelemetry Collector → Azure Monitor |
| Database | in-cluster Postgres | still in-cluster at first; managed Postgres is a values toggle |
