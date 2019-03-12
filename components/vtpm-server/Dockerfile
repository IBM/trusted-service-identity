FROM fedora:29

# we need gnutls 3.6.5 or later
# packaging error in f29 expect package forces us to remove whois-mkpasswd
RUN dnf -y update \
   && dnf -y remove whois-mkpasswd \
   && dnf -y install git python gnutls gnutls-utils tpm-tools trousers swtpm \
       expect nmap-ncat procps-ng

# Build patched trousers
# We HAVE TO enable debugging on tcsd to make this work -- at least
# then it work with the TPM on sbct-4.pok.ibm.com -- WEIRD!!
RUN dnf -y install automake autoconf libtool gcc openssl-devel \
  && git clone https://github.com/stefanberger/trousers.git trousers \
  && cd trousers \
  && git checkout origin/fix_authfail -b my_fix_authfail \
  && ./bootstrap.sh \
  && ./configure --prefix=/usr \
  && make -j $(nproc) \
  && make -j $(nproc) install \
  && ./configure --prefix=/usr --enable-debug \
  && make -j$(nproc) clean \
  && make -j$(nproc) all \
  && cp src/tcsd/tcsd /sbin/tcsd

# Build patched python-gnutls needed for patched jwcrypto
RUN git clone https://github.com/stefanberger/python-gnutls.git python-gnutls \
  && cd python-gnutls \
  && git checkout origin/privkey -b privkey \
  && dnf -y install gcc redhat-rpm-config python-devel gnutls-devel \
  && pip install enum34 \
  && python setup.py build \
  && python setup.py install \
  && python setup.py test

# Build patched jwcrypto needed to support TPM 1.2
RUN git clone https://github.com/stefanberger/jwcrypto jwcrypto \
  && cd jwcrypto \
  && git checkout origin/pkcs11_via_gnutls -b pkcs11_via_gnutls \
  && python setup.py test \
  && python setup.py install

COPY tcsd_swtpm.sh init_tpmkey.sh gen-jwt.py gen-jwt.sh validate-jwt.py run-tpm-server.sh \
	system.data.auth system.data.noauth resetlockvalue /usr/local/bin/

# Force usage of SWTPM; comment to for usage of HW TPM (once implemented)
ENV USE_SWTPM=1

# Run a test at the end
RUN USE_SWTPM=1 STATEDIR=/tmp \
    jwt=$(gen-jwt.sh \
	--iss example-issuer \
	--aud foo,bar \
	--claims=email:foo@google.com,dead:beef) \
  && echo "$jwt" \
  && bash -c "validate-jwt.py /tmp/tpmpubkey <(echo -n "$jwt") \
              && { echo 'jwt verified successfully'; exit 0; } || exit 1" \
  && rm -rf /tmp/*

# Adding support for flask
COPY requirements.txt /
RUN pip install -r requirements.txt
COPY run-server.sh server.py /usr/local/bin/

# Default values for JWT, issuer and token expiration in seconds
ARG DEFAULT_ISS="wsched@us.ibm.com"
ARG DEFAULT_TTL_SEC=30
ENV ISS=${DEFAULT_ISS}
ENV TTL_SEC=${DEFAULT_TTL_SEC}

CMD ["/bin/bash", "-c", "/usr/local/bin/run-tpm-server.sh"]
