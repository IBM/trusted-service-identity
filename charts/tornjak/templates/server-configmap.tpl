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
      socket_path = "{{ .Values.spireServer.socketDir }}/{{ .Values.spireServer.socketFile }}"

      {{- if .Values.oidc.enable }}
      #AWS requires the use of RSA.  EC cryptography is not supported
      ca_key_type = "rsa-2048"

      # this is to prevent frequent updates to spire-bundle
      ca_ttl = "500h"
      # to test re-attestation, continous
      agent_ttl = "5m"


      # Creates the iss claim in JWT-SVIDs.
      jwt_issuer = "https://{{ .Values.oidc.serviceName }}.{{ .Values.oidc.myDiscoveryDomain }}"

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
     {{- if .Values.attestors.x509 }}
      NodeAttestor "x509pop" {
        plugin_data {
           ca_bundle_path = "/opt/spire/sample-x509/rootCA.pem"
        }
      }
     {{- end }}
      NodeAttestor "k8s_psat" {
        plugin_data {
            clusters = {
                "{{ .Values.clustername }}" = {
                    # use_token_review_api_validation = true
                    service_account_allow_list = ["spire:spire-agent"]
                },
                {{- if .Values.attestors.k8s_psat.remoteClusters }}
                {{- range $k, $v := .Values.attestors.k8s_psat.remoteClusters }}
                "{{ $v.name }}" = {
                    service_account_allow_list = ["{{ $v.namespace | default "spire" }}:{{ $v.serviceAccount | default "spire-agent" }}"]
                    kube_config_file = "/run/spire/kubeconfigs/{{ $v.name }}"
                },
                {{- end }}
                {{- end }}
            }
        }
      }

      NodeAttestor "x509pop" {
       plugin_data {
          ca_bundle_path = "/opt/spire/sample-x509/rootCA.pem"
          reattest = true
       }
      }

      {{- if .Values.attestors.aws_iid -}}
      {{- if .Values.attestors.aws_iid.access_key_id -}}
      {{- if .Values.attestors.aws_iid.secret_access_key -}}
      NodeAttestor "aws_iid" {
          plugin_data {
            access_key_id = "{{- .Values.attestors.aws_iid.access_key_id -}}"
            secret_access_key = "{{- .Values.attestors.aws_iid.secret_access_key -}}"
            skip_block_device = {{- .Values.attestors.aws_iid.skip_block_device -}}
          }
      }

      {{- end }}
      {{- end }}
      {{- end }}

      {{- if .Values.attestors.azure_msi -}}
      {{- if .Values.attestors.azure_msi.tenants -}}
      NodeAttestor "azure_msi" {
        enabled = true
        plugin_data {
          tenants = {
            // Tenant configured with the default resource id (i.e. the resource manager)
            {{- range $k, $v := .Values.attestors.azure_msi.tenants }}
            "{{ $v.tenant }}" = {},
            {{- end }}
          }
        }
      }
      {{- end }}
      {{- end }}

      KeyManager "disk" {
        plugin_data {
          keys_path = "/run/spire/data/keys.json"
        }
      }

      {{- if not .Values.spireServer }}
      {{- if not .Values.spireServer.selfSignedCA }}
      UpstreamAuthority "disk" {
        plugin_data {
          ttl = "12h"
          key_file_path = "/run/spire/secret/bootstrap.key"
          cert_file_path = "/run/spire/secret/bootstrap.crt"
        }
      }
      {{- end }}
      {{- end }}
      Notifier "k8sbundle" {
        plugin_data {
          # This plugin updates the bundle.crt value in the spire:spire-bundle
          # ConfigMap by default, so no additional configuration is necessary.
          namespace = "{{ .Values.namespace }}"
        }
      }
    }
