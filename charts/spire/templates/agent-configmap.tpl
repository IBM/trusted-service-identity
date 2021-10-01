apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-agent
  namespace: {{ .Values.namespace }}
data:
  agent.conf: |
    agent {
      data_dir = "/run/spire"
      log_level = "DEBUG"
      server_address = "{{ .Values.spireServer.address }}"
      server_port = "{{ .Values.spireServer.port }}"
      socket_path = "{{ .Values.spireAgent.socketDir }}/{{ .Values.spireAgent.socketFile }}"
      trust_bundle_path = "/run/spire/bundle/bundle.crt"
      trust_domain = "{{ .Values.trustdomain }}"
    }
    plugins {
      {{- if .Values.aws }}
      NodeAttestor "aws_iid" {
          plugin_data {}
      }
      {{- else if .Values.azure }}
      NodeAttestor "azure_msi" {
          plugin_data {
           }
      }
      {{- else }}
      NodeAttestor "k8s_psat" {
          plugin_data {
            cluster = "{{ .Values.clustername }}"
          }
      }
      {{- end }}
      KeyManager "memory" {
        plugin_data {
        }
      }
      WorkloadAttestor "k8s" {
        plugin_data {
          {{- if .Values.azure }}
          kubelet_read_only_port = 10255
          {{- else }}
          skip_kubelet_verification = true
          {{- end }}
        }
      }
    }
