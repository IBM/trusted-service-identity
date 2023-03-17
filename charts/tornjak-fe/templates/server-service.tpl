apiVersion: v1
kind: Service
metadata:
  namespace: {{ .Values.namespace }}
  name: tornjak-fe
spec:
  type: LoadBalancer
  selector:
    app: spire-server
  ports:
    - name: tornjak-fe
      port: 3000
      targetPort: 3000