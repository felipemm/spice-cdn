{{/*
Namespace for namespaced resources.

Argo CD normally passes the Application destination namespace into Helm. If that
is missing, Helm defaults Release.Namespace to "default", which would create
Services/Deployments in the wrong namespace while Argo tracks "control-plane".

Prefer explicit .Values.targetNamespace, else a non-default Release.Namespace,
else fall back to "control-plane" for this chart.
*/}}
{{- define "control-plane.namespace" -}}
{{- if .Values.targetNamespace -}}
{{- .Values.targetNamespace -}}
{{- else if and .Release.Namespace (ne .Release.Namespace "default") -}}
{{- .Release.Namespace -}}
{{- else -}}
control-plane
{{- end -}}
{{- end }}
