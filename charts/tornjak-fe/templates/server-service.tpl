apiVersion: v1
kind: Service
metadata:
  namespace: {{ include "tornjak-fe.namespace" . }}
  name: tornjak-fe
spec:
  type: ClusterIP
  selector:
    app: tornjak-fe
  ports:
    - name: tornjak-fe
      port: 3000
      targetPort: 3000