{{/*
Name helpers for the wrapper chart (parent release).
*/}}
{{- define "spice-instance.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "spice-instance.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{- define "spice-instance.spiceaiServiceName" -}}
{{- printf "%s-spiceai" .Release.Name -}}
{{- end }}

{{- define "spice-instance.ownerLayerSlug" -}}
{{- required "ownerLayerSlug is required (DNS-like slug for cost / owner-layer-slug label)" .Values.ownerLayerSlug | trim -}}
{{- end }}

{{/*
Dedicated hostname for Flight SQL gRPC Ingress. Must differ from ingress.host: two Prefix "/" rules on the
same host make nginx route gRPC to the HTTP backend (404). Default: <first-label>-flight.<rest>, e.g.
spice-demo.127.0.0.1.nip.io -> spice-demo-flight.127.0.0.1.nip.io
*/}}
{{- define "spice-instance.flightSqlIngressHost" -}}
{{- if and .Values.ingress.flightSQL (ne (.Values.ingress.flightSQL.host | default "" | trim) "") -}}
{{- .Values.ingress.flightSQL.host | trim -}}
{{- else -}}
{{- $h := required "ingress.host is required when ingress.enabled" .Values.ingress.host | trim -}}
{{- if not (contains "." $h) -}}
{{- fail "ingress.host must contain a dot to derive flightSQL host (<name>-flight.<rest>); set ingress.flightSQL.host explicitly" -}}
{{- end -}}
{{- $parts := splitList "." $h -}}
{{- $first := index $parts 0 -}}
{{- $rest := trimPrefix (printf "%s." $first) $h -}}
{{- printf "%s-flight.%s" $first $rest -}}
{{- end -}}
{{- end }}
