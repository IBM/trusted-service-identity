apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: spire-agent
  namespace: {{ .Values.namespace }}
  labels:
    app: spire-agent
spec:
  selector:
    matchLabels:
      app: spire-agent
  template:
    metadata:
      namespace: spire
      labels:
        app: spire-agent
    spec:
      hostPID: true
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      serviceAccountName: "spire-agent"
      initContainers:
        - name: init
          # This is a small image with wait-for-it, choose whatever image
          # you prefer that waits for a service to be up. This image is built
          # from https://github.com/lqhl/wait-for-it
          image: gcr.io/spiffe-io/wait-for-it
          args: ["-t", "30", "{{ .Values.spireAddress }}:{{ .Values.spirePort }}"]
      containers:
        - name: spire-agent
          image: {{ .Values.spireAgentImg }}:{{ .Values.spireVersion }}
          securityContext:
            # privilaged is needed to create socket and bundle files
            privileged: true
          args: ["-config", "/run/spire/config/agent.conf"]
          volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
              readOnly: true
            - name: spire-agent-socket
              mountPath: /run/spire/sockets
              readOnly: false
            - name: spire-bundle
              mountPath: /run/spire/bundle
              readOnly: true
            - name: spire-agent-token
              mountPath: /var/run/secrets/tokens
          livenessProbe:
            exec:
              command:
                - /opt/spire/bin/spire-agent
                - healthcheck
                - -socketPath
                - /run/spire/sockets/agent.sock
            failureThreshold: 2
            initialDelaySeconds: 15
            periodSeconds: 60
            timeoutSeconds: 3
      volumes:
        - name: spire-config
          configMap:
            name: spire-agent
        - name: spire-bundle
          configMap:
            name: spire-bundle
        - name: spire-agent-socket
          hostPath:
            path: /run/spire/sockets
            type: DirectoryOrCreate
        - name: spire-agent-token
          projected:
            sources:
            - serviceAccountToken:
                path: spire-agent
                expirationSeconds: 600
                audience: spire-server
