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
