{{- if .Values.tornjak }}
{{- if .Values.tornjak.config }}
{{- if .Values.tornjak.config.separateFrontend }}
apiVersion: v1
kind: Service
metadata:
  name: tornjak-frontend-service
spec:
  type: LoadBalancer
  selector:
    app: spire-server
  ports:
    - name: tornjak-frontend
      port: 3000
      targetPort: 3000
---
{{- end }}
{{- end }}
{{- end }}
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
          # image: {{ .Values.spireServer.img }}:milosz
          image: {{ .Values.spireServer.img }}:config
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
      - name: frontend
        # TODO change to official image name
        image: ghcr.io/spiffe/tornjak-fe:latest
        # image: ghcr.io/spiffe/tornjak-fe:1.5.1
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
        env:
        {{- if .Values.tornjak.config.frontend }}
        {{- if .Values.tornjak.config.frontend.authServerURL }}
        - name: REACT_APP_AUTH_SERVER_URI
          value: {{ .Values.tornjak.config.frontend.authServerURL }}
        {{- end }}
        {{- if .Values.tornjak.config.frontend.apiServerURL }}
        - name: REACT_APP_API_SERVER_URI
          value: {{ .Values.tornjak.config.frontend.apiServerURL }}
        {{- end }}
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
