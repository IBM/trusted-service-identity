FROM ubuntu:18.04

RUN apt update && \
    apt install -y curl && \
    apt install coreutils && \
    apt install -y wget && \
    apt install -y unzip && \
    apt install -y jq && \
    apt install -y vim && \
    apt install -y python3 && \
    apt install -y python3-pip


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

COPY sidecar/run-sidecar-bash.sh /usr/local/bin
COPY sidecar/run-sidecar-python.py /usr/local/bin

COPY sidecar/requirements.txt /usr/local/bin/requirements.txt
RUN pip3 install -r /usr/local/bin/requirements.txt

RUN cd /root


# Use shell script to obtain files
# CMD ["/usr/local/bin/run-sidecar-bash.sh", "~/inputfile.txt"] 

# Use python script to obtain files
CMD ["python3", "/usr/local/bin/run-sidecar-python.py", "~/inputfile.txt"]

# CMD ["/bin/bash", "-c", "tail -f /dev/null"]
