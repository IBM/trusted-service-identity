FROM fedora:29

RUN dnf -y install git python gnutls gnutls-utils tpm-tools trousers

# Build patched gnutls
RUN dnf -y install make automake autoconf autogen libtool gettext texinfo \
  tar gzip perl nettle guile p11-kit gperf libtasn1-devel libidn2-devel \
  libunistring-devel gawk bison trousers-devel \
  gettext-devel patch rsync wget which nettle-devel p11-kit-devel gcc \
  && dnf -y update nettle \
  && git clone https://gitlab.com/stefanberger/gnutls.git gnutls \
  && cd gnutls \
  && git checkout tags/gnutls_3_6_5 -b gnutls_3_6_5 \
  && ./bootstrap \
  && ./configure --prefix=/usr --with-tpm --disable-doc \
  && make -j $(nproc) \
  && make -j $(nproc) install

RUN dnf -y install expect nmap-ncat procps-ng
RUN dnf -y install swtpm --enablerepo=updates-testing

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
