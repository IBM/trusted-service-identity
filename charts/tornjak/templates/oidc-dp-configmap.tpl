apiVersion: v1
kind: ConfigMap
metadata:
  name: oidc-discovery-provider
  namespace: {{ .Values.namespace }}
data:
  oidc-discovery-provider.conf: |
    log_level = "INFO"
    # TODO: Replace MY_DISCOVERY_DOMAIN with the FQDN of the Discovery Provider that you will configure in DNS
    domain = "oidc-tornjak.{{ .Values.MY_DISCOVERY_DOMAIN }}"
    listen_socket_path = "/run/oidc-discovery-provider/server.sock"
    #acme {
    #  tos_accepted = true
    #  email = "lumjjb@gmail.com"
    #}
    log_level = "error"
    server_api {
      address = "unix:///run/spire/sockets/registration.sock"
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
