FROM myubuntu:latest
RUN apt update && \
    apt install -y curl vim && \
    apt install -y wget && \
    apt install -y unzip && apt install -y openssl && \
    rm -rf /var/lib/apt/lists/*

RUN wget https://releases.hashicorp.com/vault/0.10.3/vault_0.10.3_linux_amd64.zip && unzip vault_0.10.3_linux_amd64.zip
