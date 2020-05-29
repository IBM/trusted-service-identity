FROM ubuntu:18.04

ARG ARCH

RUN apt update && \
    apt install -y curl && \
    apt install -y wget && \
    apt install -y unzip && \
    apt install -y jq && \
    apt install -y vim

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/${ARCH}/kubectl && \
    chmod +x kubectl
RUN wget https://releases.hashicorp.com/vault/1.0.3/vault_1.0.3_linux_amd64.zip && \
    unzip vault_1.0.3_linux_amd64.zip && \
    mv vault /usr/local/bin/ && \
    rm -f vault_1.0.3_linux_amd64.zip

COPY ./setup-vault-cli.sh /setup-vault-cli.sh
COPY ./test-vault-cli.sh /test-vault-cli.sh

# Default values for vault client setup
ARG DEFAULT_VAULT_ADDR="http://vault:8200"
ARG DEFAULT_VAULT_ROLE="tsi-role-rcni"
ENV VAULT_ADDR=${DEFAULT_VAULT_ADDR}
ENV VAULT_ROLE=${DEFAULT_VAULT_ROLE}

CMD ["/bin/bash", "-c", "while true; do sleep 10; done;"]
