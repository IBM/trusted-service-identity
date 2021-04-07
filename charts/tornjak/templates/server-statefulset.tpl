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
          # image: tsidentity/tornjak-spire-server:latest
          image: tsidentity/tornjak-spire-server:{{ .Values.spireVersion }}
          securityContext:
            # privilaged is needed to access mounted files
            privileged: true
          args:
            - -config
            - /run/spire/config/server.conf
          ports:
            - containerPort: 8081
          securityContext:
            privileged: true
          volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
              readOnly: true
            - name: spire-data
              mountPath: /run/spire/data
              readOnly: false
            - name: spire-server-socket
              mountPath: /run/spire/sockets
              readOnly: false
          livenessProbe:
            exec:
              command: ["/opt/spire/bin/spire-server", "healthcheck", "-registrationUDSPath", "/run/spire/sockets/registration.sock"]
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
          readinessProbe:
            exec:
              command: ["/opt/spire/bin/spire-server", "healthcheck", "-registrationUDSPath", "/run/spire/sockets/registration.sock", "--shallow"]
            initialDelaySeconds: 5
            periodSeconds: 5
        - name: spire-oidc
          image: gcr.io/spiffe-io/oidc-discovery-provider:0.12.0
          args:
          - -config
          - /run/spire/oidc/config/oidc-discovery-provider.conf
          ports:
          - containerPort: 443
            name: spire-oidc-port
          volumeMounts:
          - name: spire-server-socket
            mountPath: /run/spire/sockets
            readOnly: true
          - name: spire-oidc-config
            mountPath: /run/spire/oidc/config/
            readOnly: true
          - name: spire-data
            mountPath: /run/spire/data
            readOnly: false
          - name: spire-oidc-socket
            mountPath: /run/oidc-discovery-provider/
          readinessProbe:
            exec:
              command: ["/bin/ps", "aux", " ||", "grep", "oidc-discovery-provider -config /run/spire/oidc/config/oidc-discovery-provider.conf"]
            initialDelaySeconds: 5
            periodSeconds: 5
        - name: nginx-oidc
          image: nginx:latest
          ports:
          - containerPort: 8989
            name: nginx-oidc-port
          args:
          - nginx
          - -g
          - "daemon off;"
          - -c
          - /run/spire/oidc/config/nginx.conf
          volumeMounts:
          - name: spire-oidc-config
            mountPath: /run/spire/oidc/config/
            readOnly: true
          - name: spire-oidc-socket
            mountPath: /run/oidc-discovery-provider/
      volumes:
        - name: spire-config
          configMap:
            name: spire-server
        - name: spire-server-socket
          hostPath:
            path: /run/spire/sockets/server
            type: DirectoryOrCreate
        - name: spire-oidc-config
          configMap:
            name: oidc-discovery-provider
        - name: spire-oidc-socket
          emptyDir: {}
        # remove if using volumeClaimTemplates
        - name: spire-data
          hostPath:
            path: /var/spire-data
            type: DirectoryOrCreate

#  volumeClaimTemplates:
#    - metadata:
#        name: spire-data
#        namespace: {{ .Values.namespace }}
#      spec:
#        accessModes:
#          - ReadWriteOnce
#        resources:
#          requests:
#            storage: 1Gi
