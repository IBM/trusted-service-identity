vault status
vault secrets enable pki
# Increase the TTL by tuning the secrets engine. The default value of 30 days may
# be too short, so increase it to 1 year:
vault secrets tune -max-lease-ttl=8760h pki
vault delete pki/root
vault write pki/root/generate/internal common_name=my-website.com \
    ttl=8760h -format=json

# export OUT=$(vault write pki/root/generate/internal common_name=my-website.com \
#     ttl=8760h -format=json)
# echo $OUT
# echo $OUT | jq -r '.["data"].issuing_ca' > jwks.json
