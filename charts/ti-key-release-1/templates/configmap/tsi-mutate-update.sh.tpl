{{ define "tsi-mutate-update.sh.tpl" }}

export TI_SA_TOKEN=$(kubectl -n {{ .Values.namespace }} get sa ti-sa -o jsonpath='{.secrets[0].name}')
cat /tmp/ti-key-release/tsi-mutate-configmap.yaml | sed -e "s|\${TI_SA_TOKEN}|${TI_SA_TOKEN}|g" > /tmp/configmap.new.yaml
/kubectl create -f /tmp/configmap.new.yaml -n {{ .Values.namespace }}
/tmp/ti-key-release/certmaker.sh --namespace trusted-identity

{{ end }}
