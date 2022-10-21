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
    {{- if .Values.tornjak.config.key1 }}"
      key1: "{{- .Values.tornjak.config.key1 }}"
    {{- end }}
      key2: "value2"
    }
{{- end }}
{{- end }}
