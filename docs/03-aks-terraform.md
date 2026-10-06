# Step 3 — AKS with Terraform, CI/CD and Azure Monitor

**Goal:** provision a real AKS cluster with Terraform, through a pull-request workflow like a real team's: **plan on PR, review, approve, apply on merge, deploy**. Use no stored secrets anywhere, and send all telemetry to Azure Monitor.

## The big picture

```
                                  GitHub
  PR ──► Terraform Plan ─(OIDC: plan identity, read-only)──┐
  merge ─► Terraform Apply ─┐                              │
           [approval: dev]  ├(OIDC: apply identity)────────┤
         Deploy to AKS ─────┘                              ▼
                                                        Azure
  ┌ rg-shiplog-mgmt ─────────┐ ┌ rg-shiplog-observability ─────────────┐ ┌ rg-shiplog-dev-aks ──────────────┐
  │ Terraform state (blob)   │ │ Log Analytics ◄─┐                      │ │ AKS (Entra RBAC, Cilium)         │
  │ id-shiplog-github-plan   │ │ App Insights    ├─ DCR ◄─ DCE ◄────────┼─┼─ OTel Collector (Workload ID)   │
  │ id-shiplog-github-apply  │ │ Monitor wkspace ◄┘ (OTLP endpoints)    │ │ ACR (AcrPull for the nodes)      │
  └─ bootstrap (local) ──────┘ └─ stack: observability ────────────────┘ └─ stack: aks-dev ─────────────────┘
```

| Stack | Path | State | Applied by |
|---|---|---|---|
| bootstrap | `infra/bootstrap` | **local file** (gitignored) | you, once, from your laptop |
| observability | `infra/azure/observability` | `observability.tfstate` | CI |
| aks-dev | `infra/azure/aks` | `aks-dev.tfstate` | CI |

They're separate stacks because they have **different lifecycles**. You'll destroy and recreate the cluster often to save money, but you want to keep its telemetry history, and the bootstrap pieces almost never change.

## Cost (centralus, approximate)

| Resource | ~Monthly | Notes |
|---|---|---|
| 2 × Standard_B2als_v2 nodes | $55 | autoscaler can add a 3rd |
| OS disks, Postgres disk | $12 | |
| Load balancer + 2 public IPs | $25 | outbound + web |
| ACR Basic | $5 | |
| AKS control plane | $0 | Free tier, no SLA |
| Log Analytics / App Insights | ~$0 | first 5 GB/month free; 1 GB/day hard cap |
| State storage | <$1 | |
| **Total while the cluster runs** | **≈ $95/month ≈ $3/day** | |

**Destroy the cluster when you're not using it:** Actions → *Terraform Destroy* → `aks-dev`. Observability and bootstrap cost almost nothing to keep.

---

## One-time setup

### 1. Tools

```powershell
winget install Hashicorp.Terraform
winget install GitHub.cli
az aks install-cli          # installs kubelogin (and kubectl), needed for Entra ID sign-in to AKS
```

Open a new terminal afterwards so PATH updates.

### 2. Bootstrap (from your laptop)

```powershell
cd infra/bootstrap
copy terraform.tfvars.example terraform.tfvars   # check the values
az login                                         # as the subscription Owner
terraform init
terraform plan -out tfplan                       # read it!
terraform apply tfplan
terraform output github_variables_commands
```

It registers resource providers, then creates the state storage account and the two GitHub identities. Expect about 3–5 minutes; provider registration is the slow part.

> **Keep `infra/bootstrap/terraform.tfstate`.** It's the only record of the bootstrap resources. If it's lost, nothing breaks, but you'd need `terraform import` to manage them again. It's gitignored on purpose because state can contain sensitive values.

### 3. GitHub configuration

```powershell
gh auth login
# paste the commands printed by `terraform output github_variables_commands`, then:
gh variable set WEB_ALLOWED_CIDRS --body "$((Invoke-RestMethod https://api.ipify.org))/32"
```

`WEB_ALLOWED_CIDRS` limits who can reach the app's public IP: just you. Change it when your IP changes, or use a comma-separated list.

Then, in the repo on GitHub, go to **Settings → Environments → New environment → `dev`**:

- **Required reviewers:** add yourself. Every apply or deploy waits for your click.
- **Deployment branches and tags:** *Selected branches* → `main`. ⚠️ This matters for security: the apply identity trusts *any job in the `dev` environment*, so the environment must only be usable from `main`. A PR branch could otherwise add `environment: dev` to a workflow and get write access to Azure.

And **Settings → Branches → Add rule** for `main`: require a pull request, and require these status checks to pass: `plan · observability`, `plan · aks-dev`, `fmt · validate · tflint · checkov`, plus the App CI and Chart CI jobs.

### 4. The first run

1. Open the PR for this step. **Terraform Plan** runs, and two comments appear with the plans for `observability` and `aks-dev`. The aks-dev plan shows a *warning* that observability isn't applied yet, so the collector's DCR permission is left out of this first plan. That's expected.
2. Merge it. **Terraform Apply** waits for your approval (Actions tab → *Review deployments*). It applies observability, then aks-dev. The AKS cluster takes about 10 minutes.
3. **Deploy to AKS** starts automatically after the apply and also needs approval. It builds and pushes the images to ACR, installs the collector and the app, runs `helm test`, and prints the app's URL in the run summary: `http://shiplog-dev-aj11131.centralus.cloudapp.azure.com`.

---

## How the security works

### No secrets anywhere: OIDC federation

GitHub signs a short-lived token for each job, describing **where** the job runs:

| Job | Token subject | Trusted by |
|---|---|---|
| any PR workflow | `repo:aj11131@54563379/shiplog@1407845180:pull_request` | plan identity (Reader + state lock) |
| job with `environment: dev` | `repo:aj11131@54563379/shiplog@1407845180:environment:dev` | apply identity (Contributor + constrained RBAC admin) |

The `@54563379` and `@1407845180` are the owner and repo IDs. GitHub's **immutable subjects** add them so that if the repo is renamed, or deleted and someone re-creates one with the same name, the new repo's tokens don't match. Check the exact prefix with `gh api repos/aj11131/shiplog/actions/oidc/customization/sub`. If a sign-in fails with `AADSTS700213: No matching federated identity record`, the error message shows the subject GitHub actually sent; compare it with this table.

Azure exchanges that token for an Azure access token only if the subject matches a federated credential exactly. There's no client secret to leak, rotate or expire. That's also why the GitHub "variables" aren't secrets: client IDs only *identify* an identity, they don't grant anything.

### Least privilege, in layers

- **Plan can't change anything.** Reader on the subscription, plus blob access to the state container (a plan writes a lock).
- **Apply can't make itself Owner.** It holds *Role Based Access Control Administrator* with an **ABAC condition** that forbids granting or removing Owner, User Access Administrator or RBAC Administrator. A compromised workflow can create resources and assign normal roles (like AcrPull), but can't escalate itself. See [bootstrap/main.tf](../infra/bootstrap/main.tf).
- **State storage has no keys.** `shared_access_key_enabled = false`, so every read and write is an Entra identity with an RBAC role. That's auditable and revocable. Blob versioning keeps every previous state for recovery.
- **The cluster has no static credentials.** Local accounts are disabled, so `kubectl` always signs in through Entra ID, and Kubernetes permissions are **Azure RBAC role assignments** (in Terraform) rather than RoleBindings.
- **Pods have no Azure credentials.** The collector uses **Workload Identity**. The cluster's OIDC issuer signs its service account token; Entra trusts tokens for `system:serviceaccount:observability:otel-collector` from *this* cluster only (a federated credential); and the identity's only role is *Monitoring Metrics Publisher* on one Data Collection Rule.
- **Nodes pull from ACR with the kubelet identity** (AcrPull), so there are no image pull secrets. The ACR admin user is disabled.

### Deliberate trade-offs (good to discuss in review)

| Choice | Why | Production alternative |
|---|---|---|
| API server is public (Entra-protected) | GitHub's hosted runners have changing IPs | Private cluster + self-hosted runners, or `az aks command invoke` |
| App over plain **HTTP** on a LoadBalancer IP, restricted to your IP | No domain or TLS yet | **Gateway API** (AKS app routing) + TLS. Step 4 needs HTTPS for Entra sign-in, so it lands there |
| App Insights keeps local auth on | The browser SDK can't get Entra tokens | Server-side telemetry already uses Entra only |
| One node pool for system + apps | Cost | Separate system and user pools |
| Checkov soft-fails | A dev cluster intentionally skips some controls | Fail on agreed severities |
| Plan on PR, re-plan on apply | Simple and safe (apply always uses fresh state) | Save the PR's plan as an artifact and apply exactly that |

### Why ingress isn't used yet

Ingress-NGINX was retired upstream in March 2026, and AKS's managed NGINX loses support in November 2026. The supported path on AKS is now **Gateway API** through the app routing add-on (Istio-based, GA since April 2026). Step 4 adds it together with TLS, because Entra sign-in requires HTTPS redirect URIs. Until then the web Service is a `LoadBalancer` with `loadBalancerSourceRanges`.

## Telemetry path

```
API pod ──OTLP/gRPC──► otel-collector (same node, internalTrafficPolicy: Local)
nginx/postgres stdout ─► /var/log/pods ─► collector (filelog)
kubelet stats ─────────────────────────► collector (kubeletstats)
                                            │ + k8s metadata, cluster name, delta temporality
                                            ▼ OTLP/HTTP + Entra token (Workload Identity)
                              DCE ─► DCR ─┬─► Log Analytics (logs, traces) ─► App Insights views
                                          └─► Azure Monitor workspace (metrics)
browser ──App Insights JS SDK──────────────► App Insights
```

- The **collector config** is in [deploy/otel-collector/values-azure.yaml](../deploy/otel-collector/values-azure.yaml). It's a DaemonSet in its own namespace with Pod Security level `privileged`, because reading node log files needs a hostPath volume. Every log agent has this trade-off. It runs as root to read root-owned log files, but with every capability dropped and a read-only filesystem.
- **Cost controls:** the collector only tails the `shiplog` namespace and skips the API container (its logs already arrive over OTLP, so tailing them would double-ingest). It scrapes kubelet stats every 60s, and Log Analytics has a 1 GB/day hard cap.
- Direct OTLP ingestion into Azure Monitor became generally available in 2026. The resources are built from [Microsoft's DCE/DCR template](https://github.com/microsoft/AzureMonitorCommunity/tree/master/Azure%20Services/Azure%20Monitor/OpenTelemetry) using `azapi`, because azurerm doesn't model the OTLP data sources yet.

## Working with the cluster from your laptop

```powershell
az aks get-credentials -g rg-shiplog-dev-aks -n aks-shiplog-dev
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes -o wide
kubectl get pods -A
```

Running Terraform locally (e.g. `terraform plan` for the AKS stack):

```powershell
cd infra/azure/aks
$env:ARM_SUBSCRIPTION_ID = "6defd2a7-df6b-4dba-97cc-f76f4813244d"
$env:TF_VAR_tfstate_resource_group  = "rg-shiplog-mgmt"
$env:TF_VAR_tfstate_storage_account = "<from bootstrap output>"
terraform init -backend-config="resource_group_name=rg-shiplog-mgmt" -backend-config="storage_account_name=<...>" `
               -backend-config="container_name=tfstate" -backend-config="key=aks-dev.tfstate" -backend-config="use_azuread_auth=true"
terraform plan -var-file=env/dev.tfvars
```

Locally, Terraform uses your `az login`.

## Try this

1. **Watch a plan comment change.** Open a PR that changes `node_max_count` in `infra/azure/aks/env/dev.tfvars` from 3 to 4. The comment shows an *in-place update* to the cluster. Push a second commit and the same comment updates instead of a new one appearing.
2. **See what forces replacement.** Change `node_vm_size` in a PR and read the plan carefully: some fields are immutable, and Terraform plans **destroy-then-create**. That's the main reason to read every plan.
3. **Break formatting on purpose.** Mis-indent a `.tf` file in a PR, and the `fmt` check fails before any cloud access happens.
4. **Prove the plan identity is read-only.** In a PR, temporarily change the plan workflow to run `terraform apply`. It fails with an authorization error.
5. **Explore the telemetry.** In the portal, open Application Insights `appi-shiplog` and look at *Application map*, *Transaction search* and *Failures*. In Log Analytics, run a query and filter by `k8s.cluster.name`.
6. **Compare kind and AKS.** Run the same `kubectl` exercises from [docs/02](02-helm-kind.md) (delete pods, scale Postgres to 0, drain a node). The PVC is now an Azure Disk: watch it detach and re-attach when Postgres moves between nodes (`kubectl get volumeattachment`).
7. **Tear down and rebuild.** Destroy `aks-dev`, then re-run Terraform Apply and Deploy. In App Insights, the history from before the rebuild is still there.

## Things to verify on the first real deployment

Some of this is new enough that it can only be fully confirmed against real Azure:

- **The OTLP stream names in the endpoint URLs** (`Microsoft-OTLP-Traces`, `Microsoft-OTLP-Logs`, `Custom-Metrics-Otel`) follow Microsoft's current docs. If the collector logs `404` or `403` errors, check them against the DCR.
- **App Insights' built-in metric charts expect exponential histograms.** The API currently emits explicit-bucket histograms. Traces, logs and the application map are unaffected, but some prebuilt metric charts may be empty. That's an easy follow-up in `TelemetryExtensions.cs`.
- **The first Terraform Apply on a brand-new subscription** may need a retry if a resource provider registration is still propagating.
