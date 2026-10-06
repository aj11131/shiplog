<#
.SYNOPSIS
  Creates (or reuses) the local "shiplog" kind cluster, builds and loads the app images,
  and installs the Helm chart. Safe to re-run: it upgrades the existing release.

.EXAMPLE
  ./scripts/kind-up.ps1                 # everything
  ./scripts/kind-up.ps1 -SkipBuild      # chart changes only; reuse the loaded images
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$Namespace = 'shiplog',
    [string]$Release = 'shiplog'
)

# Native tools (docker, kind, helm) write progress to stderr, which Windows PowerShell 5.1
# treats as an error under "Stop". Failures are detected by exit code in Invoke-Checked instead.
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$cluster = 'shiplog'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Invoke-Checked {
    # Run a native command and stop if it fails (PowerShell 5.1 doesn't do this by itself).
    & $args[0] $args[1..($args.Length - 1)]
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $($args -join ' ')" }
}

foreach ($tool in 'docker', 'kind', 'kubectl', 'helm') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH. See docs/02-helm-kind.md." }
}

Step "Cluster"
if ((kind get clusters 2>$null) -contains $cluster) {
    Write-Host "kind cluster '$cluster' already exists - reusing it."
} else {
    Invoke-Checked kind create cluster --config "$root/deploy/kind/kind-config.yaml" --wait 120s
}
Invoke-Checked kubectl config use-context "kind-$cluster"

if (-not $SkipBuild) {
    Step "Build images"
    Invoke-Checked docker build -t shiplog-api:local --build-arg VERSION=0.1.0-kind "$root/src/api"
    Invoke-Checked docker build -t shiplog-web:local "$root/src/web"

    # kind nodes can't see images in your local Docker, so copy them onto every node.
    Step "Load images into kind"
    Invoke-Checked kind load docker-image shiplog-api:local shiplog-web:local --name $cluster
}

Step "metrics-server (needed by the HorizontalPodAutoscaler)"
Invoke-Checked helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
# kind's kubelets use self-signed certificates, hence --kubelet-insecure-tls (local clusters only!).
Invoke-Checked helm upgrade --install metrics-server metrics-server/metrics-server `
    --namespace kube-system --set "args={--kubelet-insecure-tls}" --wait

Step "Namespace with Pod Security 'restricted' enforced"
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -
Invoke-Checked kubectl label namespace $Namespace --overwrite `
    pod-security.kubernetes.io/enforce=restricted `
    pod-security.kubernetes.io/warn=restricted

Step "Helm install/upgrade"
helm status $Release --namespace $Namespace 2>$null | Out-Null
$isUpgrade = $LASTEXITCODE -eq 0
Invoke-Checked helm upgrade --install $Release "$root/charts/shiplog" `
    --namespace $Namespace `
    --values "$root/charts/shiplog/values-kind.yaml" `
    --wait --timeout 5m

if ($isUpgrade -and -not $SkipBuild) {
    # Same tag ("local"), new image: Kubernetes doesn't notice a change, so roll the pods ourselves.
    Step "Restart app pods to pick up the new images"
    Invoke-Checked kubectl rollout restart deployment -n $Namespace -l "app.kubernetes.io/instance=$Release,app.kubernetes.io/name=shiplog"
    Invoke-Checked kubectl rollout status deployment -n $Namespace "$Release-api" --timeout 3m
    Invoke-Checked kubectl rollout status deployment -n $Namespace "$Release-web" --timeout 3m
}

Step "Smoke test"
Invoke-Checked helm test $Release --namespace $Namespace --logs

Step "Done"
kubectl get pods -n $Namespace -o wide
Write-Host ""
Write-Host "App:        http://localhost:8090" -ForegroundColor Green
Write-Host "Telemetry:  http://localhost:18890" -ForegroundColor Green
Write-Host "Tear down:  ./scripts/kind-down.ps1"
