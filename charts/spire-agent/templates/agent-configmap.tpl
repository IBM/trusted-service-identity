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
      # server_address = "spire-server"
      # server_address = "spire-server-spire-server.tsi-roks02-5240a919746a818fd9d58aa25c34ecfe-0000.eu-de.containers.appdomain.cloud"
      server_address = "{{ .Values.spireAddress }}"
      # server_port = "8081"
      # server_port = "443"
      server_port = "{{ .Values.spirePort }}"
      socket_path = "/run/spire/sockets/agent.sock"
      trust_bundle_path = "/run/spire/bundle/bundle.crt"
      trust_domain = "{{ .Values.trustdomain }}"
    }
    plugins {
      NodeAttestor "k8s_psat" {
        plugin_data {
          # NOTE: Change this to your cluster name
          cluster = "{{ .Values.clustername }}"
        }
      }
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
