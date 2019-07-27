FROM ubuntu:18.04
RUN apt update && \
    apt install -y curl && \
    apt install -y wget && \
    apt install -y python-pip python-dev build-essential

WORKDIR /
COPY requirements.txt /
RUN pip install -r requirements.txt
COPY *.py /
COPY run-server.sh /

ARG JWKS_ARG=https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json
ENV JWKS=$JWKS_ARG

CMD ["/bin/bash", "-c", "/run-server.sh"]
