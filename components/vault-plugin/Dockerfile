FROM vault:latest 

ARG ARCH

COPY ./pkg/linux_${ARCH}/ /plugins/
COPY ./local.json /vault/config/local.json
