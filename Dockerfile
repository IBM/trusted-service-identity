FROM scratch
ADD ti-webhook /ti-webhook
ENTRYPOINT ["./ti-webhook"]
