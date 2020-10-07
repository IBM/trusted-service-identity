FROM ubuntu:18.04
RUN apt update && \
    apt install -y curl jq vim && \
    apt install -y openssl

# general, software attestation:
COPY soft-attestation.sh /usr/local/bin/

# IsecL attestation:
COPY isecl-attestation.sh	isecl-get-openssl-cnf.sh /usr/local/bin/

ARG DEFAULT_HOSTDIR="/host"
ENV HOSTDIR=${DEFAULT_HOSTDIR}

CMD ["/bin/bash", "-c", "/usr/local/bin/soft-attestation.sh"]
