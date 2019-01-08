FROM ubuntu:16.04
RUN apt update && \
    apt install -y curl && \
    apt install -y wget && \
    apt install -y vim && \
    apt install -y python-pip python-dev build-essential

WORKDIR /
COPY requirements.txt /
RUN pip install -r requirements.txt
COPY *.py /
COPY *.sh /
ENV KEYSTORE_URL="NOTSET"
ENV TARGET_URL="NOTSET"

CMD ["/bin/bash", "-c", "/loop.sh"]
