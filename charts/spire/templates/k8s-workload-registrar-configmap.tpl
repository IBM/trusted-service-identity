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
    # enable when direct socket access to SPIRE Server available:
    # server_socket_path = "/run/spire/sockets/registration.sock"
    agent_socket_path = "/run/spire/sockets/agent.sock"
    server_address = "{{ .Values.spireAddress }}:{{ .Values.spirePort }}"
    cluster = "{{ .Values.clustername }}"
    # enable for label based registration:
    # pod_label = "spire-workload-id"
    # enable for annotation based registration:
    pod_annotation = "spire-workload-id"
