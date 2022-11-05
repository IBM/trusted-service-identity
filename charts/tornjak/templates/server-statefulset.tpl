{{- if .Values.tornjak }}
{{- if .Values.tornjak.config }}
{{- if .Values.tornjak.config.enableUserMgment }}
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
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      serviceAccount: spire-server
      serviceAccountName: spire-server
      shareProcessNamespace: true
      terminationGracePeriodSeconds: 30
      containers:
        - name: spire-server
          image: {{ .Values.spireServer.img }}:{{ .Values.spireVersion }}
          imagePullPolicy: Always
          args:
            - -config
            - /run/spire/config/server.conf
            - -tornjak-config
            - /run/spire/tornjak-config/server.conf
          ports:
            - containerPort: 8081
              protocol: TCP
          resources: {}
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          securityContext:
            privileged: true
          volumeMounts:
            - name: tornjak-config
              mountPath: /run/spire/tornjak-config
              readOnly: true
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
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            successThreshold: 1
            timeoutSeconds: 3
            exec:
              command:
              - "/opt/spire/bin/spire-server"
              - "healthcheck"
              - "-socketPath"
              - "{{ .Values.spireServer.socketDir }}/{{ .Values.spireServer.socketFile }}"
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
        {{- if .Values.oidc.enable }}
        - name: spire-oidc
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
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          resources: {}
          volumeMounts:
            - name: spire-oidc-config
              mountPath: /run/spire/oidc/config/
              readOnly: true
            - name: spire-oidc-socket
              mountPath: {{ .Values.oidc.socketDir }}
        {{- end }}
        {{- if .Values.tornjak }}
        {{- if .Values.tornjak.config }}
        {{- if .Values.tornjak.config.enableUserMgment }}
        - name: frontend
          # image: mohammedmunirabdi/deploy-tornjak-frontend-kubernetes:latest
          # image: tsidentity/tornjak-spire-server:latest
          image: tsidentity/tornjak-fe:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          env:
            {{- if .Values.tornjak.config.authServerUri }}
            - name: REACT_APP_AUTH_SERVER_URI
              value: {{ .Values.tornjak.config.authServerUri }}
            {{- end }}
            {{- if .Values.tornjak.config.apiServerUri }}
            - name: REACT_APP_API_SERVER_URI
              value: {{ .Values.tornjak.config.apiServerUri }}
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
            path: /run/spire-server/private
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
