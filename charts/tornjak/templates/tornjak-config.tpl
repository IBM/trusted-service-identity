apiVersion: v1
kind: ConfigMap
metadata:
  name: tornjak-config
  namespace: {{ .Values.namespace }}
data:
  server.conf: |
    server {
      metadata = "insert metadata"
    }

    plugins {

    {{- if .Values.tornjak }}
    {{- if .Values.tornjak.config }}
    {{- if .Values.tornjak.config.backend }}

    {{- if .Values.tornjak.config.backend.dataStore }}
      DataStore "sql" {
        plugin_data {
          drivername = "{{ .Values.tornjak.config.backend.dataStore.driver }}"
          # TODO is this a good location?
          filename = "{{ .Values.tornjak.config.backend.dataStore.file }}"
        }
      }
      {{- end }}

      {{- if .Values.tornjak.config.enableUserMgmt }}
      UserManagement "KeycloakAuth" {
        plugin_data {
          jwksURL = "{{ .Values.tornjak.config.backend.jwksURL }}"
          redirectURL = "{{ .Values.tornjak.config.backend.redirectURL }}"
        }
      }
    {{- end }}

    {{- end }}
    {{- end }}
    {{- end }}

    }
