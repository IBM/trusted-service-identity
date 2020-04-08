FROM fedora:29

RUN dnf -y install python swtpm procps-ng uwsgi uwsgi-plugin-python2

RUN dnf -y install git openssl-devel automake autoconf libtool make file \
    && git clone https://git.code.sf.net/p/ibmtpm20tss/tss ibmtpm20tss-tss \
    && cd ibmtpm20tss-tss \
    && git checkout tags/v1.4.0 \
    && autoreconf -i \
    && ./configure --prefix=/usr --disable-tpm-1.2 \
    && make -j$(nproc) \
    && make install

# The above should work but we get an undefined reference 'verbose' in the library
# We use the following steps until this is fixed...
RUN cd ibmtpm20tss-tss \
    && cd utils \
    && make -f makefiletpm20 clean \
    && make -j$(nproc) -f makefiletpm20 all \
    && cp --preserve=links *.so /usr/lib64/ \
    && cp -rp ibmtss /usr/include

RUN dnf -y install git openssl-devel automake autoconf libtool help2man file \
    && git clone https://git.kernel.org/pub/scm/linux/kernel/git/jejb/openssl_tpm2_engine.git \
    && cd openssl_tpm2_engine \
    && git checkout tags/v2.4.0 \
    && bash ./bootstrap.sh \
    && ./configure \
    && make -j$(nproc) \
    && make install

# we absolutely need python2-cryptography otherwise we may pick up the one from pip
# and this one may cause issues; python2-crypography 2.3 works
RUN dnf -y install python2-cryptography \
    && pip install jwcrypto==0.7

COPY gen-jwt.sh EngineJWK.py gen-jwt.py run-tpm-server.sh startup_tpm.sh validate-jwt.py /usr/local/bin/

RUN jwt=$(gen-jwt.sh \
        --iss example-issuer \
        --aud foo,bar \
        --claims=email:foo@google.com,dead:beef) \
  && echo "$jwt" \
  && bash -c "validate-jwt.py $(cat /tmp/tpmkeyurl) <(echo -n "$jwt") \
              && { echo 'jwt verified successfully'; exit 0; } || exit 1" \
  && bash -c "validate-jwt.py /tmp/tpmpubkey.pem <(echo -n "$jwt") \
              && { echo 'jwt verified successfully'; exit 0; } || exit 1" \
  && rm -rf /tmp/*

# Adding support for flask
COPY requirements.txt /
RUN pip install -r requirements.txt
COPY run-jss-server.sh jss-server-priv.py jss-server-pub.py /usr/local/bin/

# Default values for JWT, issuer and token expiration in seconds
ARG DEFAULT_ISS="wsched@us.ibm.com"
ARG DEFAULT_TTL_SEC=30
ENV ISS=${DEFAULT_ISS}
ENV TTL_SEC=${DEFAULT_TTL_SEC}

CMD ["/bin/bash", "-c", "/usr/local/bin/run-tpm-server.sh"]
