# Step 4 — Entra ID sign-in and HTTPS

**Goal:** a public HTTPS site where **anyone can read** the log, **signed-in users can write**, and **only an entry's author or a `Shiplog.Admin`** can delete it. Everything is defined in Terraform and Helm and shipped through the same PR → plan → approve → deploy flow.

## The big picture

```
                       ┌──────────────── AKS ────────────────────────────────────────────┐
 browser ──https──► Azure LB ─► Gateway "shiplog" (ns: ingress) ──HTTPRoute──► web (nginx) ──► api ──► postgres
    │                  :80 ─► 301 to https (except /.well-known/acme-challenge → cert-manager)
    │                  :443 TLS cert: Let's Encrypt, issued and renewed by cert-manager
    │
    │ 1. Sign in (redirect)      ┌──────── Entra ID ────────┐
    └──────────────────────────► │ Shiplog Web (SPA)        │ 2. code + PKCE → tokens
                                 │ Shiplog API              │    access token: aud = API, scp = Entries.ReadWrite,
                                 │  scope Entries.ReadWrite │                  roles = [Shiplog.Admin]
                                 │  role  Shiplog.Admin     │
                                 └──────────────────────────┘
   3. fetch /api/... with "Authorization: Bearer <token>"  →  the API validates signature, issuer, audience, expiry
```

## What was built

| Area | Where | What |
|---|---|---|
| Graph permissions | [infra/bootstrap/main.tf](../infra/bootstrap/main.tf) | Plan: `Application.Read.All`. Apply: `Application.ReadWrite.OwnedBy` |
| App registrations | [infra/azure/identity](../infra/azure/identity) (new stack) | SPA + API registrations, scope, app role, pre-authorization |
| Gateway API | [infra/azure/aks/main.tf](../infra/azure/aks/main.tf) | AKS app routing add-on, Istio implementation (`approuting-istio`) |
| HTTPS front door | [charts/gateway](../charts/gateway) (new chart) | `Gateway`, Let's Encrypt `Issuer`, HTTP→HTTPS redirect |
| cert-manager | [deploy/cert-manager/values.yaml](../deploy/cert-manager/values.yaml) | Gateway API support turned on |
| App routing | [charts/shiplog/templates/httproute.yaml](../charts/shiplog/templates/httproute.yaml) | Attaches the web Service to the Gateway |
| API auth | [src/api/Shiplog.Api/Auth](../src/api/Shiplog.Api/Auth) | JWT validation, `entries.write` policy, `CurrentUser`, `GET /api/me` |
| SPA auth | [src/web/src/app/core/auth.service.ts](../src/web/src/app/core/auth.service.ts) | MSAL Browser v5, redirect flow, token interceptor |
| Schema | `Migrations/*/…_AddAuthorId.cs` | A nullable `AuthorId` column |
| Hardening | [src/web/nginx](../src/web/nginx) | Content-Security-Policy, HSTS over HTTPS, a no-store redirect bridge |

## One-time setup (in this order)

### 1. Re-apply bootstrap (from your laptop, on the PR branch)

The identity stack needs the CI identities to have Microsoft Graph permissions, and granting those requires a Global Administrator. That's you, not CI.

```powershell
git switch step-4-entra-https
cd infra/bootstrap
terraform init -upgrade      # installs the new azuread provider
terraform plan -out tfplan
```

Expect **`Plan: 2 to add, 0 to change, 0 to destroy`**: two `azuread_app_role_assignment.graph[...]` resources. Assigning a Graph *application permission* to an identity **is** admin consent, so there's no separate "Grant consent" click. Then:

```powershell
terraform apply tfplan
```

### 2. Open the PR, then merge

You'll get three plan comments:

| Stack | Expected | Notes |
|---|---|---|
| `observability` | No changes | |
| `identity-dev` | **8 to add** | 2 random UUIDs, the API app + identifier URI + service principal, the SPA app + service principal, and the pre-authorization |
| `aks-dev` | **1 to change** | The cluster, in place: `ingressProfile` gains Gateway API |

Merge, then approve **Terraform Apply** (identity takes seconds, and the AKS update about 3–5 minutes), then **Deploy to AKS**. The deploy now:
1. installs cert-manager;
2. deploys Shiplog, switching the web Service to `ClusterIP` (this releases the old public IP and its DNS name);
3. deploys the Gateway, which claims the DNS name with a new public IP and gets a certificate;
4. runs smoke tests over HTTPS: `/healthz`, an anonymous write must return **401**, and HTTP must redirect to HTTPS.

**Expect a few minutes of downtime** between steps 2 and 3. A zero-downtime cutover would give the Gateway a *new* hostname, switch DNS, and only then retire the old one; that needs a domain you control.

### 3. Give yourself the `Shiplog.Admin` role

CI **can't** do this on purpose. Assigning users to app roles needs the Graph permission `AppRoleAssignment.ReadWrite.All`, and an identity holding it can grant *itself* any Graph permission, which makes it effectively a tenant admin. So a human does it once:

**Portal:** Entra ID → **Enterprise applications** → *Shiplog API (dev)* → **Users and groups** → **Add user/group** → select yourself → role **Shiplog administrator** → **Assign**.

(Or run the command that `terraform output grant_admin_role_command` prints for the identity stack.)

You'll find the apps under **App registrations → All applications** rather than *Owned applications*. CI's identity is their only owner, because adding you as a co-owner would require `Application.ReadWrite.All`, a permission that can edit **every** app in the tenant.

Then **sign out and sign in again**. Roles are baked into the token when it's issued, so an existing token won't have the new role.

### 4. Tidy up

The your-IP-only rule is gone, because the site is now protected by sign-in. Delete the variable:

```powershell
gh variable delete WEB_ALLOWED_CIDRS
```

## How it works

### Two app registrations, scopes vs. roles

| | **Scope** `Entries.ReadWrite` | **App role** `Shiplog.Admin` |
|---|---|---|
| Answers | What may *this app* do on the user's behalf? | What is *this user* allowed to do? |
| Token claim | `scp` | `roles` |
| Who grants it | The user consents (here it's pre-authorized for our SPA) | An admin assigns users or groups |
| Checked by | The `entries.write` policy (every write) | `CurrentUser.CanDelete` (deleting other people's entries) |

**401 vs 403** is a distinction worth remembering. **401 Unauthorized** really means *unauthenticated*: no valid token. **403 Forbidden** means *we know who you are, and you can't do this*.

### Sign-in flow (authorization code + PKCE)

1. **Sign in:** MSAL redirects to `login.microsoftonline.com/<tenant>/oauth2/v2.0/authorize` with `response_type=code` and a **PKCE** challenge, which is a hash of a random secret generated for this one sign-in.
2. **Return:** Entra redirects back to **`/auth/redirect`**, the MSAL v5 *redirect bridge* ([main.ts](../src/web/src/main.ts)). It stashes the response and returns to the app, where `AuthService.init()` exchanges the code (plus the PKCE secret) for tokens.
3. **Store:** tokens live in **sessionStorage**, so closing the tab signs you out of the app.
4. **Call the API:** the [interceptor](../src/web/src/app/core/auth.interceptor.ts) attaches the token **only to our `/api/` calls**. Sending it to third parties (like telemetry) would hand them your identity.

### Token validation in the API

`AddJwtBearer` downloads Entra's signing keys from `https://login.microsoftonline.com/<tenant>/v2.0/.well-known/openid-configuration` and rejects any token whose signature, issuer, audience (`aud` = the API's client ID) or expiry doesn't check out. Before building the PR, I tested this against your real tenant: a hand-crafted token with the right claims but no valid signature was rejected with `invalid_token: The signature key was not found`.

### HTTPS: Gateway API + cert-manager

- **Gateway API splits ownership.** The **platform** owns the `Gateway` (listeners, TLS, public IP) in the `ingress` namespace. The **app** owns an `HTTPRoute` in its own namespace. The Gateway's `allowedRoutes` decides which namespaces may attach. This also keeps AKS-generated Istio proxy pods out of the app's *restricted* namespace.
- **cert-manager** sees the `cert-manager.io/issuer` annotation on the Gateway and requests a certificate for the HTTPS listener's hostname. For **HTTP-01** validation it temporarily adds an `HTTPRoute` for `/.well-known/acme-challenge/<token>` on port 80. An exact path match beats the catch-all redirect, so the challenge isn't redirected. Certificates renew automatically before their 90-day expiry.
- **Let's Encrypt limits production certificates** to 5 duplicates per week. If you're tearing down and redeploying a lot, switch the Issuer to staging (`tls.acme.server` in [charts/gateway/values.yaml](../charts/gateway/values.yaml)). Staging certificates aren't trusted by browsers, but the limits are generous.

### Schema change without downtime (expand/contract)

`AuthorId` is a **new nullable column**. During the rollout, old API pods (which don't know about it) and new ones run side by side against the same database, which works because adding a nullable column is backward compatible. A later "contract" step would make it required, once every row has a value. Renaming or dropping a column in a single release would break the old pods mid-rollout.

### Security headers

- **Content-Security-Policy:** only our own scripts may run, and the page may only connect to our API, Entra and Application Insights. Angular's "critical CSS inlining" was turned off because it injects an inline `onload=` handler that this policy would block.
- **HSTS** is sent only when the browser actually arrived over HTTPS (nginx checks `X-Forwarded-Proto` from the Gateway). It uses a short 1-day `max-age` because this is a test domain.

## Local development

Sign-in is **off** locally, on kind, and in CI. `Auth:Enabled=false` keeps the step 1–3 behavior: you type an author, and anyone can write or delete. To try real sign-in locally, set these on the API and the web container (`AUTH_*` env vars), using values from the identity stack's outputs:

```
Auth__Enabled=true  Auth__TenantId=<tenant>  Auth__Audience=<api_client_id>
AUTH_CLIENT_ID=<web_client_id>  AUTH_TENANT_ID=<tenant>  AUTH_API_SCOPE=<api_scope>
```

`http://localhost:4200`, `:8080` and `:8090` are registered redirect origins.

## Try this

1. **Read anonymously:** open the site in a private window. You can see the log but get a *Sign in* prompt instead of the form.
2. **Decode your token:** sign in, then open DevTools → Application → Session Storage, find the access token, and paste it into **https://jwt.ms**. Find `aud`, `iss`, `scp`, `roles`, `oid` and `exp`. The **Diagnostics** page shows what the *API* extracted from it.
3. **401 vs 403:**
   ```powershell
   curl.exe -i -X POST https://shiplog-dev-aj11131.westus3.cloudapp.azure.com/api/entries -H "Content-Type: application/json" -d '{\"message\":\"hi\"}'
   ```
   That's a 401. Now remove your `Shiplog.Admin` assignment, sign out and in again, and try deleting someone else's entry: 403. Its Delete button also disappears, because the API's `canDelete` reflects your token.
4. **Watch a certificate:** `kubectl get certificate -n ingress` and `kubectl describe certificate shiplog-tls -n ingress`. Delete the TLS secret (`kubectl delete secret shiplog-tls -n ingress`) and watch cert-manager issue a new one. Mind the Let's Encrypt limits.
5. **Inspect the Gateway:** `kubectl get gateway,httproute -A`, then `kubectl get pods -n ingress` to see the Envoy proxies AKS created. `kubectl get pods -n aks-istio-system` shows the managed control plane.
6. **CSP in action:** in DevTools on the live site, run `fetch('https://example.com')`. The browser blocks it with a CSP violation.
7. **HTTP → HTTPS:** `curl.exe -I http://shiplog-dev-aj11131.westus3.cloudapp.azure.com/` returns `301` with a `Location: https://…` header.

## Things to verify on the first real deploy

New moving parts that couldn't be exercised without Azure:

- **DNS label handover:** the Gateway's Service claims `shiplog-dev-aj11131` only after the old web LoadBalancer releases it. Azure's cloud controller retries, which can take a few minutes. If the Gateway isn't `Programmed`, check `kubectl describe svc -n ingress`.
- **Resource headroom:** the managed `istiod` (2 replicas) and the gateway proxies (2 replicas) fit within the two nodes' unreserved CPU, but there's now less room for the API to autoscale. If pods sit `Pending`, request the quota increase and add a node.
- **Pod Security:** the `ingress` namespace uses `baseline`. If AKS's generated gateway pods were ever rejected, `kubectl get events -n ingress` would say so.
