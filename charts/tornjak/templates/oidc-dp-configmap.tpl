{{- if .Values.oidc.enable }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: oidc-discovery-provider
  namespace: {{ .Values.namespace }}
data:
  oidc-discovery-provider.conf: |
    log_level = "debug"
    domain = "{{ .Values.oidc.serviceName }}.{{ .Values.oidc.myDiscoveryDomain }}"
    listen_socket_path = "{{ .Values.oidc.socketDir }}/{{ .Values.oidc.socketFile }}"
    server_api {
      address = "unix:///{{ .Values.spireServer.socketDir }}/{{ .Values.spireServer.socketFile }}"
    }
  nginx.conf: |
    user root;
    events {
            # The maximum number of simultaneous connections that can be opened by
            # a worker process.
            worker_connections 1024;
    }
    http {
            # WARNING: Don't use this directory for virtual hosts anymore.
            # This include will be moved to the root context in Alpine 3.14.
            #include /etc/nginx/conf.d/*.conf;
            server {
                    listen *:8989;
                    location / {
                            proxy_pass http://unix:/run/oidc-discovery-provider/server.sock:/;
                    }
            }
    }
{{- end }}
