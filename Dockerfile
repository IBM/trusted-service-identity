FROM alpine:latest
ADD ti-webhook /ti-webhook
ENTRYPOINT ["./ti-webhook"]
