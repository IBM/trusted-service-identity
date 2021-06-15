apiVersion: v1
kind: ConfigMap
metadata:
  name: identity-schema
  namespace: {{ .Values.namespace }}
data:
  identity-schema.yaml: |
    version: v1
    fields:
      - name: provider
        attestorSource:
          name: nodeAttestor
          group: nodeAttestor
          mapping:
          - type: aws
            field: aws_iid:*
          - type: gcloud
            field: gcp_iit:*
          - type: azure
            field: azure_msi:*
          - type: ibm
            field: iks
          - type: minikube
            field: minikube
      - name: region
        configMapSource:
          ns: kube-system
          name: cluster-info
          field: cluster-region
      - name: workload-namespace
        attestorSource:
          name: workloadAttestor
          group: workloadAttestor
          mapping:
          - type: k8s
            field: ns
      - name: workload-serviceAccount
        attestorSource:
          name: workloadAttestor
          group: workloadAttestor
          mapping:
          - type: k8s
            field: sa
      - name: workload-podname
        attestorSource:
          name: workloadAttestor
          group: workloadAttestor
          mapping:
          - type: k8s
            field: pod-name
      - name: pod-uid
        attestorSource:
          name: workloadAttestor
          group: workloadAttestor
          mapping:
          - type: k8s
            field: pod-uid
