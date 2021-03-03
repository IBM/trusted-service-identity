apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: spire-server
  namespace: {{ .Values.namespace }}
  labels:
    app: spire-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spire-server
  serviceName: spire-server
  template:
    metadata:
      namespace: {{ .Values.namespace }}
      labels:
        app: spire-server
    spec:
      serviceAccountName: spire-server
      shareProcessNamespace: true
      containers:
        - name: spire-server
          # image: gcr.io/spiffe-io/spire-server:0.11.0
          image: tsidentity/tornjak-spire-server:latest
          securityContext:
            # privilaged is needed to access mounted files
            privileged: true
          args:
            - -config
            - /run/spire/config/server.conf
          ports:
            - containerPort: 8081
          volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
              readOnly: true
            - name: spire-data
              mountPath: /run/spire/data
              readOnly: false
            - name: certs
              mountPath: /opt/spire/sample-keys
          livenessProbe:
            exec:
              command:
                - /opt/spire/bin/spire-server
                - healthcheck
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 6000
            timeoutSeconds: 3
      volumes:
        - name: spire-config
          configMap:
            name: spire-server
        - name: spire-entries
          configMap:
            name: spire-entries
        - name: spire-data
          hostPath:
            path: /var/spire-data
            type: DirectoryOrCreate
        - name: certs
          secret:
            defaultMode: 0400
            secretName: tornjak-certs
