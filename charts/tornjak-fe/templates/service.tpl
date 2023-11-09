apiVersion: v1
kind: Service
metadata:
  namespace: {{ include "tornjak-fe.namespace" . }}
  name: {{ include "tornjak-fe.fullname" . }}
spec:
  type: ClusterIP
  selector:
    app: {{ include "tornjak-fe.fullname" . }}
  ports:
    - name: tornjak-fe
      port: 3000
      targetPort: 3000