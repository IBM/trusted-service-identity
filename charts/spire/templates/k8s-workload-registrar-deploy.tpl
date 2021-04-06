apiVersion: apps/v1
kind: Deployment
metadata:
  name: spire-registrar
  namespace: {{ .Values.namespace }}
  labels:
    app: spire-registrar
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spire-registrar
  template:
    metadata:
      namespace: {{ .Values.namespace }}
      labels:
        app: spire-registrar
    spec:
      serviceAccountName: spire-k8s-registrar
      shareProcessNamespace: true
      containers:
        - name: k8s-workload-registrar
          #image: k8s-workload-registrar:latest
          image: {{ .Values.spireRegistrar }}:{{ .Values.spireVersion }}
          imagePullPolicy: Always
          securityContext:
            # privilaged is needed to create socket and bundle files
            privileged: true
          args:
            - -config
            - /run/k8s-workload-registrar/config/registrar.conf
          volumeMounts:
            - name: spire-registrar-socket
              mountPath: /run/spire/sockets
              readOnly: false
            - name: k8s-workload-registrar-config
              mountPath: /run/k8s-workload-registrar/config
              readOnly: true
      volumes:
        - name: spire-registrar-socket
          hostPath:
            path: /run/spire/sockets
            type: DirectoryOrCreate
        - name: k8s-workload-registrar-config
          configMap:
            name: k8s-workload-registrar
