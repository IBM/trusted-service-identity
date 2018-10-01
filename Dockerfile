FROM alpine:latest
ADD ti-webhook /ti-webhook
RUN mkdir -p /tmp
ENTRYPOINT ["./ti-webhook"]
