{{/* templates/_helpers.tpl */}}
{{- define "shopflow.name" -}}
{{- .Chart.Name -}}
{{- end -}}
 
{{- define "shopflow.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
 
{{- define "shopflow.labels" -}}
app.kubernetes.io/name: {{ include "shopflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
 
{{- define "shopflow.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shopflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
