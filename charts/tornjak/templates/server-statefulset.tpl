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
      serviceAccount: spire-server
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
          protocol: TCP
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
        - name: certs
          mountPath: /opt/spire/sample-keys
        - name: spire-server-socket
          mountPath: {{ .Values.spireServer.socketDir }}
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
          successThreshold: 1
          timeoutSeconds: 3
      {{- if .Values.oidc.enable }}
        readinessProbe:
          failureThreshold: 3
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
          exec:
            command:
            - "/opt/spire/bin/spire-server"
            - "healthcheck"
            - "-socketPath"
            - "{{ .Values.spireServer.socketDir }}/{{ .Values.spireServer.socketFile }}"
            - "--shallow"
        {{- end }}

      {{- if .Values.tornjak }}
      {{- if .Values.tornjak.config }}
      {{- if .Values.tornjak.config.separateFrontend }}
      - name: tornjak-backend
        image: {{ .Values.tornjak.config.backend.img }}:{{ .Values.tornjak.config.version }}
        startupProbe:
          httpGet:
            scheme: HTTP
            path: /api/tornjak/serverinfo
            port: 10000  
          failureThreshold: 3
          initialDelaySeconds: 5
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 5
      {{- else }}
      - name: tornjak
        image: {{ .Values.tornjak.config.img }}:{{ .Values.tornjak.config.version }}
        startupProbe:
          httpGet:
            scheme: HTTP
            port: 3000  
          failureThreshold: 6
          initialDelaySeconds: 60
          periodSeconds: 30
          successThreshold: 1
          timeoutSeconds: 10

        env:

        {{- if .Values.tornjak.config.frontend }}
        
        {{- if .Values.tornjak.config.enableUserMgmt }}
        {{- if .Values.tornjak.config.frontend.authServerURL }}
        - name: REACT_APP_AUTH_SERVER_URI
          value: {{ .Values.tornjak.config.frontend.authServerURL }}
        {{- end }}
        {{- end }}

        {{- if .Values.tornjak.config.frontend.apiServerURL }}
        - name: REACT_APP_API_SERVER_URI
          value: {{ include "tornjak.apiURL" . }}          
        {{- end }}
        
        {{- end }}

      {{- end }}
      {{- end }}
      {{- end }}

        imagePullPolicy: Always
        args:
        - -c
        - /run/spire/config/server.conf
        - -t
        - /run/spire/tornjak-config/server.conf
        ports:
        - containerPort: 8081
          protocol: TCP
        securityContext:
          # privileged is needed to access mounted files (e.g. /run/spire/data)
          # not needed if using volumeClaimTemplates and sockets
          privileged: true
        volumeMounts:
        - name: tornjak-config
          mountPath: /run/spire/tornjak-config
          readOnly: true
        - name: spire-config
          mountPath: /run/spire/config
          readOnly: true
        - name: spire-server-socket
          mountPath: {{ .Values.tornjak.config.backend.socketDir }}
        # livenessProbe:
        startupProbe:
          httpGet:
            scheme: HTTP
            port: 3000  
          failureThreshold: 6
          initialDelaySeconds: 60
          periodSeconds: 30
          successThreshold: 1
          timeoutSeconds: 10

      {{- if .Values.oidc.enable }}
      - name: spire-oidc
        # TODO: OIDC image higher than 1.1.x causes compatibility issues
        image: {{ .Values.oidc.image }}:1.1.5
        imagePullPolicy: IfNotPresent
        args:
        - -config
        - /run/spire/oidc/config/oidc-discovery-provider.conf
        ports:
        - containerPort: 443
          name: spire-oidc-port
          protocol: TCP
        resources: {}
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
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
        - name: spire-data
          mountPath: /run/spire/data
        - name: spire-oidc-socket
          mountPath: {{ .Values.oidc.socketDir }}
        readinessProbe:
          failureThreshold: 3
          initialDelaySeconds: 5
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 1
          exec:
            command:
            - /bin/ps
            - aux
            - ' ||'
            - grep
            - oidc-discovery-provider -config /run/spire/oidc/config/oidc-discovery-provider.conf

      - name: nginx-oidc
        image: nginx:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8989
          name: nginx-oidc-port
          protocol: TCP
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

      {{- if .Values.tornjak }}
      {{- if .Values.tornjak.config }}
      {{- if .Values.tornjak.config.separateFrontend }}
      - name: tornjak-frontend
        image: {{ .Values.tornjak.config.frontend.img }}:{{ .Values.tornjak.config.version }}
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
        env:
        {{- if .Values.tornjak.config.frontend }}
        
        {{- if .Values.tornjak.config.enableUserMgmt }}
        {{- if .Values.tornjak.config.frontend.authServerURL }}
        - name: REACT_APP_AUTH_SERVER_URI
          value: {{ .Values.tornjak.config.frontend.authServerURL }}
        {{- end }}
        {{- end }}

        {{- if .Values.tornjak.config.frontend.apiServerURL }}
        - name: REACT_APP_API_SERVER_URI
          value: {{ .Values.tornjak.config.frontend.apiServerURL }}
        {{- end }}
        startupProbe:
          httpGet:
            scheme: HTTP
            port: 3000  
          failureThreshold: 6
          initialDelaySeconds: 60
          periodSeconds: 30
          successThreshold: 1
          timeoutSeconds: 10

        
        {{- end }}
      {{- end }}
      {{- end }}
      {{- end }}
      
      volumes:
      {{- if .Values.tornjak }}
      {{- if .Values.tornjak.config }}
      - name: tornjak-config
        configMap:
          defaultMode: 420
          name: tornjak-config
      {{- end }}
      {{- end }}
      - name: spire-config
        configMap:
          name: spire-server
          defaultMode: 420
      - name: certs
        secret:
          defaultMode: 256
          secretName: tornjak-certs
      - name: spire-server-socket
        hostPath:
          path: {{ .Values.spireServer.socketDir }}
          type: DirectoryOrCreate
      {{- if .Values.oidc.enable }}
      - name: spire-oidc-socket
        emptyDir: {}
      - name: spire-oidc-config
        configMap:
          defaultMode: 420
          name: oidc-discovery-provider
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
