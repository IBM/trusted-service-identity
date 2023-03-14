{{/*
Create URL for accessing Tornjak Backend
*/}}
{{- define "tornjak.apiURL" -}}
{{- if .Values.tornjak.config.backend.ingress }}
{{- $url := print "http://" .Values.tornjak.config.backend.ingress }}
{{- $url }}
{{- else }}
{{- default .Values.tornjak.config.frontend.apiServerURL }}
{{- end }}
{{- end }}

{{/*
Create URL for accessing Tornjak Frontend
*/}}
{{- define "tornjak.FrontendURL" -}}
{{- if .Values.tornjak.config.frontend.ingress }}
{{- $feurl := print "http://" .Values.tornjak.config.frontend.ingress }}
{{- $feurl }}
{{- else }}
{{- $feurl := print "http://localhost:3000" }}
{{- $feurl }}
{{- end }}
{{- end }}