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
      DataStore "sql" {
        plugin_data {
          drivername = "sqlite3"
          filename = "./agentlocaldb" #TODO is this a good location
        }
      }

      UserManagement "KeycloakAuth" {
        plugin_data {
          jwksURL = "http://keycloak.tornjak-02-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud/realms/tornjak/protocol/openid-connect/certs"
          redirectURL = "http://keycloak.tornjak-02-9d995c4a8c7c5f281ce13d5467ff6a94-0000.us-south.containers.appdomain.cloud/realms/tornjak/protocol/openid-connect/auth?client_id=Tornjak-React-auth"
        }
      }
    }
