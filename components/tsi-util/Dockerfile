FROM ubuntu:18.04
RUN apt update && \
    apt install -y curl jq vim && \
    apt install -y openssl

# install yq required for xform YAML to JSON
RUN apt-get install -y software-properties-common && \
    add-apt-repository ppa:rmescandon/yq && \
    apt update && apt install -y yq

RUN cd /usr/local/bin && \
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x kubectl

COPY secret-maker.sh /usr/local/bin/

# run it forever
CMD ["/bin/bash", "-c", "tail -f /dev/null"]
