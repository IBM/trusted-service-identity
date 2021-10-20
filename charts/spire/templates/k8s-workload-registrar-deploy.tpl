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
          image: {{ .Values.spireRegistrar.img }}:{{ .Values.spireVersion }}
          imagePullPolicy: Always
          securityContext:
            # TODO: review this, maybe applicable for OpenShift only:
            # privilaged is needed to create socket and bundle files
            privileged: true
          args:
            - -config
            - /run/k8s-workload-registrar/config/registrar.conf
          volumeMounts:
            - name: spire-registrar-socket
              mountPath: {{ .Values.spireAgent.socketDir }}
              readOnly: false
            - name: k8s-workload-registrar-config
              mountPath: /run/k8s-workload-registrar/config
              readOnly: true
      volumes:
        - name: spire-registrar-socket
          hostPath:
            path: {{ .Values.spireAgent.socketDir }}
            type: DirectoryOrCreate
        - name: k8s-workload-registrar-config
          configMap:
            name: k8s-workload-registrar
