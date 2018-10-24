FROM ubuntu:16.04
RUN apt update && \
    apt install -y curl && \
    apt install -y wget && \
    apt install -y unzip
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl
RUN wget https://releases.hashicorp.com/vault/0.10.3/vault_0.10.3_linux_amd64.zip && unzip vault_0.10.3_linux_amd64.zip
RUN rm -f vault_0.10.3_linux_amd64.zip
RUN echo "gen-vault-cert " > /info
CMD ["/bin/bash", "-c", "cat /pod-metadata/ti-secret && \
cp /skeys/v3_ext v3_ext && \
echo \"URI.1 = trusted-identity://$(cat /pod-metadata/ti-identity)\" >> v3_ext && \
echo -n \"trusted-identity:$(cat /pod-metadata/ti-identity)|\" >> /sidecar/claims && \
echo \"URI.2 = pod://$(cat /pod-metadata/ti-pod-name)\" >> v3_ext && \
echo -n \"pod:$(cat /pod-metadata/ti-pod-name)|\" >> /sidecar/claims && \
echo \"URI.3 = images://$(cat /pod-metadata/ti-images)\" >> v3_ext && \
# if multiple, output each image as a separate line with 'image' key:
echo -n \"images:$(cat /pod-metadata/ti-images)|\" >> /sidecar/claims && \
echo \"URI.4 = machineid://$(cat /host/etc/machine-id)\" >> v3_ext && \
echo -n \"machineid:$(cat /host/etc/machine-id)\" >> /sidecar/claims && \
openssl req -nodes -sha256 -newkey rsa:2048 -out CSR.csr  -keyout certs/client.key -new -config /skeys/image.conf && \
openssl x509 -req -in CSR.csr  -CA  /keys/rootCA.crt -CAkey /keys/rootCA.key -CAserial ca.srl -CAcreateserial -passin pass:gohome -out certs/client.crt -extfile v3_ext -extensions v3_req && \
/vault login -address=$(cat /skeys/address) -tls-skip-verify $(cat /keys/root-token) && \
/vault write -address=$(cat /skeys/address) -tls-skip-verify auth/cert/certs/$(cat /pod-metadata/ti-pod-name) display_name=\"$(cat /pod-metadata/ti-pod-name)\"  certificate=@certs/client.crt  ttl=3600 "]
#/kubectl create secret generic $(cat /pod-metadata/ti-secret) --from-file=certs/ -o yaml --dry-run | /kubectl replace -f - ; /kubectl label secret      $(cat /pod-metadata/ti-secret) ti-pod-name=$(cat /pod-metadata/ti-pod-name)"]
#cat /pod-metadata/name;sleep 10; .
#/kubectl create secret generic $(cat /pod-metadata/ti-secret) --from-literal=vault_cert=secretcert-$(cat /pod-metadata/ti-identity) -o yaml --dry-run | /kubectl replace -f - ; /kubectl label secret $(cat /pod-metadata/ti-secret) ti-pod-name=$(cat /pod-metadata/ti-pod-name)
