apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: spire-server-role
rules:
  - apiGroups: ["authentication.k8s.io"]
    resources: ["tokenreviews"]
    verbs: ["get", "watch", "list", "create"]
  - apiGroups: [""]
    resources: ["nodes","pods"]
    verbs: ["list","get"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["spire-bundle"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spire-server-binding
subjects:
  - kind: ServiceAccount
    name: spire-server
    namespace: {{ .Values.namespace }}
roleRef:
  kind: ClusterRole
  name: spire-server-role
  apiGroup: rbac.authorization.k8s.io
