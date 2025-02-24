{{/*
Expand the name of the chart.
*/}}
{{- define "up42-file-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
