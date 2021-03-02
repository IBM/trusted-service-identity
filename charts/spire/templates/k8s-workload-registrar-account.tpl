apiVersion: v1
kind: ServiceAccount
metadata:
  name: spire-k8s-registrar
  namespace: {{ .Values.namespace }}
