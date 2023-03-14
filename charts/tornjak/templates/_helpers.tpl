{{/*
Create the name of the service account to use
*/}}
{{- define "tornjak.apiURL" -}}
{{- if .Values.tornjak.config.backend.ingress }}
{{- $url := print "http://" .Values.tornjak.config.backend.ingress }}
{{- $url }}
{{- else }}
{{- default .Values.tornjak.config.frontend.apiServerURL }}
{{- end }}
{{- end }}
