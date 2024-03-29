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
  name: tornjak-be-http
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: tornjak-be-http
      port: 10000
      targetPort: 10000
      protocol: TCP
  selector:
    app: spire-server
---
apiVersion: v1
kind: Service
metadata:
  name: tornjak-be-tls
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: tornjak-be-tls
      port: 20000
      targetPort: 20000
      protocol: TCP
  selector:
    app: spire-server
---
apiVersion: v1
kind: Service
metadata:
  name: tornjak-be-mtls
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: tornjak-be-mtls
      port: 30000
      targetPort: 30000
      protocol: TCP
  selector:
    app: spire-server
---
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