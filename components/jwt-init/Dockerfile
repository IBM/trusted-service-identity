FROM ubuntu:18.04

RUN apt update && \
    apt install -y curl && \
    apt install coreutils && \
    apt install -y wget && \
    apt install -y unzip && \
    apt install -y jq && \
    apt install -y vim

# install yq required for xform YAML to JSON
RUN apt-get install -y software-properties-common && \
    add-apt-repository ppa:rmescandon/yq && \
    apt update && apt install -y yq

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x kubectl
RUN wget https://releases.hashicorp.com/vault/1.4.2/vault_1.4.2_linux_amd64.zip && \
    unzip vault_1.4.2_linux_amd64.zip && \
    mv vault /usr/local/bin/ && \
    rm -f vault_1.4.2_linux_amd64.zip

COPY run-sidecar.sh execute-get-token.sh execute-get-vault-secrets.sh \
    get-vault-secrets.sh /usr/local/bin/

COPY test-vault-cli.sh /test-vault-cli.sh

# Default value for NEW_JWT_WAIT_SEC must be a little shorter than TTL_SEC
ARG DEFAULT_JWT_TTL_SEC=30
ENV JWT_TTL_SEC=${DEFAULT_JWT_TTL_SEC}
# Default values for vault client setup
ARG DEFAULT_VAULT_ADDR="http://vault:8200"
ARG DEFAULT_SECRET_REFRESH_SEC=45
ENV VAULT_ADDR=${DEFAULT_VAULT_ADDR}
ENV SECRET_REFRESH_SEC=${DEFAULT_SECRET_REFRESH_SEC}

CMD ["/bin/bash", "-c", "/usr/local/bin/run-sidecar.sh"]
