FROM ubuntu:16.04
RUN apt update && \
    apt install -y openssl
#    apt install -y openssl && \
#    apt install -y python python-pip


# we absolutely need python2-cryptography otherwise we may pick up the one from pip
# and this one may cause issues
#RUN apt install -y python-cryptography \
#    && pip install jwcrypto

COPY init-node.sh /usr/local/bin/


# Default values for JWT, issuer and token expiration in seconds
#ARG DEFAULT_ISS="wsched@us.ibm.com"
#ARG DEFAULT_TTL_SEC=30
#ENV ISS=${DEFAULT_ISS}
#ENV TTL_SEC=${DEFAULT_TTL_SEC}

ARG DEFAULT_PRIVATE_DIR="/host/tsi-secure"
ENV PRIVATEDIR=${DEFAULT_PRIVATE_DIR}

CMD ["/bin/bash", "-c", "/usr/local/bin/init-node.sh"]
