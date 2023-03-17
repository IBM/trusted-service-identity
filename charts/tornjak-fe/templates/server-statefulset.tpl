apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: tornjak-fe
  namespace: {{ .Values.namespace }}
  labels:
    app: tornjak-fe
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tornjak-fe
  serviceName: tornjak-fe
  template:
    metadata:
      namespace: {{ .Values.namespace }}
      labels:
        app: tornjak-fe
    spec:
      serviceAccount: tornjak-fe
      serviceAccountName: tornjak-fe
      shareProcessNamespace: true
      containers:
      
 

      

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

     

