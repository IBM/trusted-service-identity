FROM ubuntu:18.04
RUN apt update && \
    apt install -y curl && \
    apt install coreutils

COPY execute-get-key.sh /usr/local/bin/

# Default value for NEW_JWT_WAIT_SEC must be a little shorter than TTL_SEC
ARG DEFAULT_JWT_TTL_SEC=30
ENV JWT_TTL_SEC=${DEFAULT_JWT_TTL_SEC}

CMD ["/bin/bash", "-c", "/usr/local/bin/execute-get-key.sh"]
