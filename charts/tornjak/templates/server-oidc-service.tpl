{{- if .Values.oidc.enable }}
# Service definition for the admission webhook
apiVersion: v1
kind: Service
metadata:
  name: spire-oidc
  namespace: {{ .Values.namespace }}
spec:
  type: LoadBalancer
  selector:
    app: spire-server
  ports:
    - name: https
      port: 443
      targetPort: nginx-oidc-port
{{- end }}
