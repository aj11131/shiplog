{{/*
Base name for all resources. "shiplog" release -> "shiplog"; "demo" release -> "demo-shiplog".
*/}}
{{- define "shiplog.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Per-component name, e.g. shiplog-api. Call with (dict "root" $ "component" "api"). */}}
{{- define "shiplog.componentName" -}}
{{- printf "%s-%s" (include "shiplog.fullname" .root) .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels used to select a component's pods. Must never change after the first install. */}}
{{- define "shiplog.selectorLabels" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* Full label set: the selector labels plus recommended metadata labels. */}}
{{- define "shiplog.labels" -}}
{{ include "shiplog.selectorLabels" . }}
app.kubernetes.io/part-of: shiplog
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end -}}

{{/* Full image reference. Call with (dict "root" $ "image" .Values.api.image). */}}
{{- define "shiplog.image" -}}
{{- $tag := .root.Values.image.tag | default .root.Chart.AppVersion -}}
{{- with .root.Values.image.registry -}}
{{- printf "%s/%s:%s" . $.image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository $tag -}}
{{- end -}}
{{- end -}}

{{/* Pod/container security settings that satisfy the "restricted" Pod Security Standard. */}}
{{- define "shiplog.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "shiplog.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/* ---------- Database connection (in-cluster subchart or external) ---------- */}}

{{- define "shiplog.db.host" -}}
{{- if .Values.postgres.enabled -}}
{{- printf "%s-postgres" .Release.Name -}}
{{- else -}}
{{- required "database.external.host is required when postgres.enabled=false" .Values.database.external.host -}}
{{- end -}}
{{- end -}}

{{- define "shiplog.db.secretName" -}}
{{- if .Values.postgres.enabled -}}
{{- printf "%s-postgres" .Release.Name -}}
{{- else -}}
{{- required "database.external.existingSecret is required when postgres.enabled=false" .Values.database.external.existingSecret -}}
{{- end -}}
{{- end -}}

{{/* The password is injected via $(DB_PASSWORD), which Kubernetes expands from the env var defined earlier. */}}
{{- define "shiplog.db.connectionString" -}}
{{- if .Values.postgres.enabled -}}
{{- printf "Host=%s;Port=5432;Database=%s;Username=%s;Password=$(DB_PASSWORD);SSL Mode=Disable" (include "shiplog.db.host" .) .Values.postgres.auth.database .Values.postgres.auth.username -}}
{{- else -}}
{{- with .Values.database.external -}}
{{- printf "Host=%s;Port=%v;Database=%s;Username=%s;Password=$(DB_PASSWORD);SSL Mode=%s" (include "shiplog.db.host" $) .port .name .username .sslMode -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "shiplog.db.passwordKey" -}}
{{- if .Values.postgres.enabled -}}password{{- else -}}{{ .Values.database.external.passwordKey }}{{- end -}}
{{- end -}}

{{/* Where the API sends telemetry: explicit endpoint, else the dev dashboard, else nowhere. */}}
{{- define "shiplog.otlpEndpoint" -}}
{{- if .Values.telemetry.otlpEndpoint -}}
{{- .Values.telemetry.otlpEndpoint -}}
{{- else if .Values.devDashboard.enabled -}}
{{- printf "http://%s:18889" (include "shiplog.componentName" (dict "root" . "component" "dashboard")) -}}
{{- end -}}
{{- end -}}
