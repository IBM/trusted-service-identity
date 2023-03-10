{{- if .Values.tornjak }}
{{- if .Values.tornjak.config }}
{{- if .Values.tornjak.config.frontend }}
{{- if .Values.tornjak.config.frontend.ingress }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tornjak-fe-ingress
  namespace: {{ .Values.namespace }}
spec:
  rules:
    # provide the actual Ingress for `host` value:
    # use the following command to get the subdomain:
    #    ibmcloud ks cluster get --cluster <cluster-name> | grep Ingress
    # any prefix can be added (e.g.):
    #  host: tsi-vault.my-tsi-cluster-xxxxxxxxxxx-0000.eu-de.containers.appdomain.cloud
  - host: {{ .Values.tornjak.config.frontend.ingress }}
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: tornjak-frontend-service
            port: 
              number: 3000
{{- end }}
{{- end }}
{{- end }}
{{- end }}