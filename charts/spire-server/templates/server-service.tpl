apiVersion: v1
kind: Service
metadata:
  name: spire-server
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: grpc
      port: 8081
      targetPort: 8081
      protocol: TCP
  selector:
    app: spire-server
---
apiVersion: v1
kind: Service
metadata:
  name: tornjak-http
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: t-http
      port: 10000
      targetPort: 10000
      protocol: TCP
  selector:
    app: spire-server
---
apiVersion: v1
kind: Service
metadata:
  name: tornjak-tls
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: t-tls
      port: 20000
      targetPort: 20000
      protocol: TCP
  selector:
    app: spire-server
---
apiVersion: v1
kind: Service
metadata:
  name: tornjak-mtls
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: t-mtls
      port: 30000
      targetPort: 30000
      protocol: TCP
  selector:
    app: spire-server
