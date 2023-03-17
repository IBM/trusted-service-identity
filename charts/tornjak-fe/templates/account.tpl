{{- if not .Values.openShift }}
# apiVersion: v1
# kind: Namespace
#metadata:
#  name: {{ .Values.namespace }}
#---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spire-server
  namespace: {{ .Values.namespace }}
{{- end }}
