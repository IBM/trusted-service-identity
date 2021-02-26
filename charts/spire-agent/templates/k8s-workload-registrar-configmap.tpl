apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-workload-registrar
  namespace: {{ .Values.namespace }}
data:
  registrar.conf: |
    log_level = "debug"
    mode = "reconcile"
    trust_domain = "{{ .Values.trustdomain }}"
    # server_socket_path = "/run/spire/sockets/registration.sock"
    agent_socket_path = "/run/spire/sockets/agent.sock"
    server_address = "spire-server:8081"
    cluster = "{{ .Values.clustername }}"
    # enable label based registration:
    # pod_label = "spire-workload-id"
    pod_annotation = "spire-workload-id"
