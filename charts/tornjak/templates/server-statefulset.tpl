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
          image: {{ .Values.spireServer.img }}:{{ .Values.spireVersion }}
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
              mountPath: {{ .Values.spireServer.socketDir }}
              readOnly: false
            {{- if .Values.attestors.k8s_psat.remoteClusters }}
            - name: kubeconfigs
              mountPath: /run/spire/kubeconfigs
            {{- end }}
          livenessProbe:
            exec:
              command:
              - "/opt/spire/bin/spire-server"
              - "healthcheck"
              - "-socketPath"
              - "{{ .Values.spireServer.socketDir }}/{{ .Values.spireServer.socketFile }}"
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
          {{- if .Values.oidc.enable }}
          readinessProbe:
            exec:
              command:
              - "/opt/spire/bin/spire-server"
              - "healthcheck"
              - "-socketPath"
              - "{{ .Values.spireServer.socketDir }}/{{ .Values.spireServer.socketFile }}"
              - "--shallow"
            initialDelaySeconds: 5
            periodSeconds: 10
          {{- end }}
        {{- if .Values.oidc.enable }}
        - name: spire-oidc
          # TODO: errors for OIDC images higher than 1.1.x
          #  image: {{ .Values.oidc.image }}:{{ .Values.spireVersion }}
          image: {{ .Values.oidc.image }}:1.1.5
          args:
          - -config
          - /run/spire/oidc/config/oidc-discovery-provider.conf
          ports:
          - containerPort: 443
            name: spire-oidc-port
          securityContext:
              # privileged is needed to access mounted files (e.g. /run/spire/data)
              # not needed if using volumeClaimTemplates and sockets
              privileged: true
          volumeMounts:
          - name: spire-server-socket
            mountPath: {{ .Values.spireServer.socketDir }}
            # readOnly: true
          - name: spire-oidc-config
            mountPath: /run/spire/oidc/config/
            readOnly: true
          - name: spire-data
            mountPath: /run/spire/data
            readOnly: false
          - name: spire-oidc-socket
            mountPath: {{ .Values.oidc.socketDir }}
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
            mountPath: {{ .Values.oidc.socketDir }}
        {{- end }}
      volumes:
        - name: spire-config
          configMap:
            name: spire-server
        - name: certs
          secret:
            defaultMode: 0400
            secretName: tornjak-certs
        {{- if .Values.attestors.k8s_psat.remoteClusters }}
        - name: kubeconfigs
          secret:
            defaultMode: 0400
            secretName: kubeconfigs
        {{- end }}
        {{- if .Values.oidc.enable }}
        - name: spire-server-socket
          hostPath:
            path: {{ .Values.spireServer.socketDir }}
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
