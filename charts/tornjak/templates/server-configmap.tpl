apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-bundle
  namespace: {{ .Values.namespace }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-server
  namespace: {{ .Values.namespace }}
data:
  server.conf: |
    server {
      bind_address = "0.0.0.0"
      bind_port = "8081"
      trust_domain = "{{ .Values.trustdomain }}"
      data_dir = "/run/spire/data"
      log_level = "DEBUG"
      default_svid_ttl = "1h"
      socket_path = "{{ .Values.spireServerSocket }}"

{{- if .Values.OIDC.enable }}
      #AWS requires the use of RSA.  EC cryptography is not supported
      ca_key_type = "rsa-2048"

      # Creates the iss claim in JWT-SVIDs.
      jwt_issuer = "https://{{ .Values.OIDC.serviceName }}.{{ .Values.OIDC.MY_DISCOVERY_DOMAIN }}"

      experimental {
        // Turns on the bundle endpoint (required, true)
        bundle_endpoint_enabled = true

        // The address to listen on (optional, defaults to 0.0.0.0)
        // bundle_endpoint_address = "0.0.0.0"

        // The port to listen on (optional, defaults to 443)
        bundle_endpoint_port = 8443
      }
{{- end }}

      ca_subject = {
        country = ["US"],
        organization = ["SPIFFE"],
        common_name = "",
      }
    }
    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "sqlite3"
          connection_string = "/run/spire/data/datastore.sqlite3"
        }
      }
      NodeAttestor "k8s_psat" {
        plugin_data {
            clusters = {
                "{{ .Values.clustername }}" = {
                    # use_token_review_api_validation = true
                    service_account_allow_list = ["spire:spire-agent"]
                },
                {{- if .Values.k8s_psat.remoteClusters }}
                {{- range $k, $v := .Values.k8s_psat.remoteClusters }}
                "{{ $v.name }}" = {
                    service_account_whitelist = ["{{ $v.namespace | default "spire" }}:{{ $v.serviceAccount | default "spire-agent" }}"]
                    kube_config_file = "/run/spire/kubeconfigs/{{ $v.name }}"
                },
                {{- end }}
                {{- end }}
            }
        }
      }
      {{- if .Values.aws_iid -}}
      {{- if .Values.aws_iid.access_key_id -}}
      {{- if .Values.aws_iid.secret_access_key -}}
      NodeAttestor "aws_iid" {
          plugin_data {
            access_key_id = "{{- .Values.aws_iid.access_key_id -}}"
            secret_access_key = "{{- .Values.aws_iid.secret_access_key -}}"
            skip_block_device: {{- .Values.aws_iid.skip_block_device -}}
          }
      }
      {{- end }}
      {{- end }}
      {{- end }}
      NodeResolver "noop" {
        plugin_data {}
      }
      KeyManager "disk" {
        plugin_data {
          keys_path = "/run/spire/data/keys.json"
        }
      }
      {{- if not .Values.selfSignedCA }}
      UpstreamAuthority "disk" {
        plugin_data {
          ttl = "12h"
          key_file_path = "/run/spire/secret/bootstrap.key"
          cert_file_path = "/run/spire/secret/bootstrap.crt"
        }
      }
      {{- end }}
      Notifier "k8sbundle" {
        plugin_data {
          # This plugin updates the bundle.crt value in the spire:spire-bundle
          # ConfigMap by default, so no additional configuration is necessary.
          namespace = "{{ .Values.namespace }}"
        }
      }
    }
