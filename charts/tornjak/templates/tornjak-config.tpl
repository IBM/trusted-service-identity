{{- if .Values.tornjak }}
{{- if .Values.tornjak.config }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: tornjak-config
  namespace: {{ .Values.namespace }}
data:
  server.conf: |
    server {
      {{- range $key, $val := .Values.tornjak.config }}
      {{ $key }}: {{ $val | quote }}
      {{- end }}
    }
{{- end }}
{{- end }}
