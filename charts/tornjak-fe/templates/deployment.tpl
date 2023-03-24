apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "tornjak-fe.fullname" . }}
  namespace: {{ include "tornjak-fe.namespace" . }}
  labels:
    app: {{ include "tornjak-fe.fullname" . }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ include "tornjak-fe.fullname" . }}
  template:
    metadata:
      namespace: {{ include "tornjak-fe.namespace" . }}
      labels:
        app: {{ include "tornjak-fe.fullname" . }}
    spec:
      shareProcessNamespace: true
      containers:
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
        - name: REACT_APP_API_SERVER_URI
          value: {{ .Values.tornjak.config.frontend.apiServerURL }}          
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