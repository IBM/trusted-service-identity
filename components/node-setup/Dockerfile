FROM ubuntu:18.04
RUN apt update && \
    apt install -y curl jq vim && \
    apt install -y openssl

RUN cd /usr/local/bin && \
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x kubectl

COPY init-node.sh /usr/local/bin/


# Default values for JWT, issuer and token expiration in seconds
#ARG DEFAULT_ISS="wsched@us.ibm.com"
#ARG DEFAULT_TTL_SEC=30
#ENV ISS=${DEFAULT_ISS}
#ENV TTL_SEC=${DEFAULT_TTL_SEC}

ARG DEFAULT_PRIVATE_DIR="/host/tsi-secure"
ENV PRIVATEDIR=${DEFAULT_PRIVATE_DIR}

CMD ["/bin/bash", "-c", "/usr/local/bin/init-node.sh"]
