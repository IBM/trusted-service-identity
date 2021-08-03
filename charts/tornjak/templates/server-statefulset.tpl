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
          image: {{ .Values.tornjakImg }}:{{ .Values.spireVersion }}
          imagePullPolicy: Always
          args:
            - -config
            - /run/spire/config/server.conf
          ports:
            - containerPort: 8081
          securityContext:
            # privileged is needed to access mounted files (e.g. /run/spire/data)
            # not needed if using volumeClaimTemplates and sockets
            privileged: true
          volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
              readOnly: true
            - name: spire-data
              mountPath: /run/spire/data
              readOnly: false
            - name: certs
              mountPath: /opt/spire/sample-keys
            - name: spire-server-socket
              mountPath: /run/spire/sockets
              readOnly: false
{{- if .Values.multiCluster.remoteClusters }}
            - name: kubeconfigs
              mountPath: /tmp/kubeconfig
{{- end }}
          livenessProbe:
            exec:
              command:
              - "/opt/spire/bin/spire-server"
              - "healthcheck"
              - "-registrationUDSPath"
              - "{{ .Values.spireServerSocket }}"
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
{{- if .Values.OIDC.enable }}
          readinessProbe:
            exec:
              command:
              - "/opt/spire/bin/spire-server"
              - "healthcheck"
              - "-registrationUDSPath"
              - "{{ .Values.spireServerSocket }}"
              - "--shallow"
            initialDelaySeconds: 5
            periodSeconds: 10
{{- end }}
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
            # TODO: This needs to be revisited.
            # the following code looks correct, but it breaks the test:
            # command: ["/bin/ps", "aux", " |",  "grep", "oidc-discovery-provider -config /run/spire/oidc/config/oidc-discovery-provider.conf", " |", "grep -v", "dumb-init"]
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
        - name: certs
          secret:
            defaultMode: 0400
            secretName: tornjak-certs
{{- if .Values.multiCluster.remoteClusters }}
        - name: kubeconfigs
          secret:
            defaultMode: 0200
            secretName: kubeconfigs
{{- end }}
{{- if .Values.OIDC.enable }}
        - name: spire-server-socket
          hostPath:
            path: {{ .Values.spireServerSocket }}
            type: DirectoryOrCreate
        - name: spire-oidc-socket
          emptyDir: {}
        - name: spire-oidc-config
          configMap:
            name: oidc-discovery-provider
{{- else }}
        - name: spire-server-socket
          emptyDir: {}
        - name: spire-entries
          configMap:
            name: spire-entries
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
