FROM ubuntu:16.04
RUN apt update && apt install -y curl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl
RUN echo "gen-vault-cert " > /info
CMD ["/bin/bash", "-c", "/kubectl cluster-info ;cat /pod-metadata/name; /kubectl create secret generic ti-secret-$(cat /pod-metadata/name) --from-literal=vault_cert=secretcert;"]
#cat /pod-metadata/name;sleep 10; .
