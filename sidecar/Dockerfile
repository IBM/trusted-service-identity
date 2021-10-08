FROM ubuntu:18.04

RUN apt update && \
    apt install -y curl && \
    apt install coreutils && \
    apt install -y wget && \
    apt install -y unzip && \
    apt install -y jq && \
    apt install -y vim


# install Spire agent cli:
RUN VERSION=1.0.2 && \
    wget https://github.com/spiffe/spire/releases/download/v${VERSION}/spire-${VERSION}-linux-x86_64-glibc.tar.gz && \
    tar zvxf spire-${VERSION}-linux-x86_64-glibc.tar.gz && \
    mkdir -p /opt/spire/bin && \
    mv /spire-${VERSION}/bin/spire-agent /opt/spire/bin/ && \
    rm -rf spire-${VERSION}/ && \
    rm -f spire-${VERSION}-linux-x86_64-glibc.tar.gz

# install Vault client:
RUN wget https://releases.hashicorp.com/vault/1.4.2/vault_1.4.2_linux_amd64.zip && \
    unzip vault_1.4.2_linux_amd64.zip && \
    mkdir -p /usr/local/bin/ && \
    mv vault /usr/local/bin/ && \
    rm -f vault_1.4.2_linux_amd64.zip

# install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
   unzip awscliv2.zip && \
   ./aws/install && \
   rm -rf aws && \
   rm -f awscliv2.zip

COPY sidecar/run-sidecar.sh /usr/local/bin

RUN cd /root

# run it forever
CMD ["/bin/bash", "-c", "tail -f /dev/null"]
