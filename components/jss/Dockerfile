FROM ubuntu:16.04
RUN apt update && \
    apt install -y openssl && \
    apt install -y python python-pip


# we absolutely need python2-cryptography otherwise we may pick up the one from pip
# and this one may cause issues
RUN apt install -y python-cryptography \
    && pip install jwcrypto

COPY gen-jwt.sh gen-jwt.py run-jss-server.sh validate-jwt.py /usr/local/bin/

# RUN jwt=$(gen-jwt.sh \
#        --iss example-issuer \
#        --aud foo,bar \
#        --claims=email:foo@google.com,dead:beef) \
#  && echo "$jwt" \
#  && bash -c "validate-jwt.py $(cat /tmp/tpmkeyurl) <(echo -n "$jwt") \
#              && { echo 'jwt verified successfully'; exit 0; } || exit 1" \
#  && bash -c "validate-jwt.py /tmp/tpmpubkey.pem <(echo -n "$jwt") \
#              && { echo 'jwt verified successfully'; exit 0; } || exit 1" \
#  && rm -rf /tmp/*

# Adding support for flask
COPY requirements.txt /
RUN pip install -r requirements.txt
COPY run-web-server.sh web-server.py /usr/local/bin/

# Default values for JWT, issuer and token expiration in seconds
ARG DEFAULT_ISS="wsched@us.ibm.com"
ARG DEFAULT_TTL_SEC=30
ENV ISS=${DEFAULT_ISS}
ENV TTL_SEC=${DEFAULT_TTL_SEC}

CMD ["/bin/bash", "-c", "/usr/local/bin/run-jss-server.sh"]
