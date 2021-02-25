FROM gcr.io/spiffe-io/spire-agent:0.11.0
COPY register-agent-join-token.sh /usr/local/bin

WORKDIR /usr/local/bin
ENTRYPOINT /bin/sh
CMD ["/usr/local/bin/register-agent-join-token.sh"]
