FROM ubuntu:18.04
RUN apt update && \
    apt install -y wget unzip && \
    apt install -y curl jq vim && \
    apt install -y openssl

# install yq required for xform YAML to JSON
RUN apt-get install -y software-properties-common && \
    add-apt-repository ppa:rmescandon/yq && \
    apt update && apt install -y yq

RUN cd /usr/local/bin && \
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x kubectl

RUN wget https://releases.hashicorp.com/vault/1.4.2/vault_1.4.2_linux_amd64.zip && \
    unzip vault_1.4.2_linux_amd64.zip && \
    mv vault /usr/local/bin/ && \
    rm -f vault_1.4.2_linux_amd64.zip

COPY secret-maker.sh /usr/local/bin/
COPY getClusterInfo.sh /usr/local/bin/
COPY load-sample-policies.sh /usr/local/bin/
COPY register-JSS.sh /usr/local/bin/
COPY vault-tpl/ /vault-tpl
COPY vault-setup.sh /usr/local/bin/
COPY setIdentity.sh getOpensslcnf.sh /usr/local/bin/

# run it forever
CMD ["/bin/bash", "-c", "tail -f /dev/null"]
