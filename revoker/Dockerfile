FROM ubuntu:16.04
RUN apt update && \
    apt install -y wget && \
    apt install -y unzip
RUN wget https://releases.hashicorp.com/vault/0.10.3/vault_0.10.3_linux_amd64.zip && unzip vault_0.10.3_linux_amd64.zip
COPY ti-revoker /ti-revoker
COPY vault_revoke.sh /vault_revoke.sh
ENTRYPOINT ["/ti-revoker"]
