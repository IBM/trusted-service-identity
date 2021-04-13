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
          image: tsidentity/tornjak-spire-server:{{ .Values.spireVersion }}
          imagePullPolicy: Always
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
              command:
              - "/opt/spire/bin/spire-server"
              - "healthcheck"
              {{- if .Values.OIDC.enable }}
              - "-registrationUDSPath"
              - "/run/spire/sockets/registration.sock"
              {{- end }}
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
          readinessProbe:
            exec:
              command:
              - "/opt/spire/bin/spire-server"
              - "healthcheck"
              {{- if .Values.OIDC.enable }}
              - "-registrationUDSPath"
              - "/run/spire/sockets/registration.sock"
              - "--shallow"
              {{- end }}
            initialDelaySeconds: 5
            periodSeconds: 5

        {{- if .Values.OIDC.enable }}
        - name: spire-oidc
          image: gcr.io/spiffe-io/oidc-discovery-provider:{{ .Values.spireVersion }}
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
{{- end }}

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

{{- if .Values.OIDC.enable }}
        - name: spire-oidc-socket
          emptyDir: {}
{{- end }}

        # remove if using volumeClaimTemplates
        - name: spire-data
          hostPath:
            path: /var/spire-data
            type: DirectoryOrCreate
# To persist the SPIRE data through volume claims instead of the hostPath, use
# the following model:
#
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
