# vTPM for Trusted Identity

## Build the Image
In order to push the image to public Artifactory registry, you need to obtain an
access and create an [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key). The repository name is `trustedseriviceidentity`

Execute the docker login and push the image:

```console
docker login trustedseriviceidentity
Username: <your-user-id>
Password: <API-key>

make all
make docker-push
```

## Deploy the vTPM Server and Service
Once image is created and pushed to the public registry (Artifactory), deploy
an instance of the vTPM server, one per cluster. This instance must be deployed
in the same namespace as the Trusted Identity.

```console
kubectl -n trusted-identity create -f vtpm-service.yaml
```

Start another container in the same namespace, and connect there:
```console
kubectl create -f examples/myubuntu.yaml -n trusted-identity
kubectl -n trusted-identity exec -it <pod-id> /bin/bash
```

Now you should be able to make calls to vTPM Server:
```console
# get JWKS
curl vtpm-service:8012/getJWKS

{ "keys":[ {"e":"AQAB","kty":"RSA","n":"sWfG-O68HgMXq-ZXjZ0OglaRVyNPb8eztJCbfe1sCYmqh5o1J6x9Yz_q-AXkThmAFS0NV1oh6UjFM_3W3yPVeZS5_IHILeho6m7cz0r97TAf9mY6dgvPNO22J2hrkyf2ZhQL2D3vQJQ5Ox4l_3q_OgoOaRfL03JQVOXj06rvkmXQcndcfBJ82l7h9JskBxoo9YWiGF-m5BCwIQ_8QAtbGDr1FEI_C79XXQpCyMaCkZwD9WxXq-Rhu5JuRc47-PMEKQrDEnSWAQsKeZ3gKmgcedggHXjo0tw22M_S8WYfdJyn4NvEKuoUM1Y4IHSbSlrjciOiNesoGSvQK-GvJ9bzcQ"}]}

# get JWT token, by passing claims:
curl vtpm-service:8012/getJWT?"cluster-name=EUcluster&cluster-region=eu-de&images=trustedseriviceidentity/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c&iss=wsched@us.ibm.com&machineid=266c2075dace453da02500b328c9e325&pod=myubuntu-698b749889-j4xdv"

eyJhbGciOiJSUzI1NiIsImtpZCI6bnVsbCwidHlwIjoiSldUIn0.eyIiOiIiLCJjbHVzdGVyLW5hbWUiOiJFVWNsdXN0ZXIiLCJjbHVzdGVyLXJlZ2lvbiI6ImV1LWRlIiwiZXhwIjoxNTQzOTQxMDg2LCJpYXQiOjE1NDM5Mzc0ODYsImltYWdlcyI6InJlcy1rb21wYXNzLWtvbXBhc3MtZG9ja2VyLWxvY2FsLmFydGlmYWN0b3J5LnN3Zy1kZXZvcHMuY29tL215dWJ1bnR1OmxhdGVzdEBzaGEyNTY6NWIyMjRlMTFmMGU4ZGFmMzVkZWI5YWViYzg2MjE4ZjFjNDQ0ZDJiODhmODljNTc0MjBhNjFiMWIzYzI0NTg0YyIsImlzcyI6IndzY2hlZEB1cy5pYm0uY29tIiwibWFjaGluZWlkIjoiMjY2YzIwNzVkYWNlNDUzZGEwMjUwMGIzMjhjOWUzMjUiLCJwb2QiOiJteXVidW50dS02OThiNzQ5ODg5LWo0eGR2Iiwic3ViIjoiZXhhbXBsZS1pc3N1ZXIifQ.gJNoPY-mKzqqjw-B44CNEpgfQl3j6lyD4o_VTZNNcTTKGbj_p7SzAT63E5U9Yw_qcM80nDcZrotEQqb7tL9beH1JVg0bwsl_1sXmk4j8p_DB8j0kkM2BlsibmxAi3YSQApzYdi84hb9dlDLqKHc9CGghPil91mZwChYazT_482qgnaBt4DOmb39vy8mx5H4oWAN8VqlDjtRJ0hoGHun3o7bzLkvLS7DDhTTsz4twfkzMmdEk0m49FZJ-27ZNg1NrqpCr8TygWsDg7O2yhDfTJ8As0MnYWnYSQXweCqnj12FK5hXI8FxFMDsW2L2Kt37EJVX_yIiKEv4kZMOi28Fb-A
```


## Low-level TPM Info:

Build and test-run it using the following commands:

```
  docker build -t jwt-sidecar .
  docker run -ti --rm jwt-sidecar \
   gen-jwt.sh --iss example-issuer --aud foo,bar --claims=email:foo@google.com,dead:beef
```

If you have a hardware TPM you can then also try to run the following
command. Note that no process may be using /dev/tpm0 when it is passed
to the container and you MUST know the owner and SRK passwords
that the TPM 1.2 has in case it is already owned. If the TPM 1.2 is
not owned, ownership will be taken then and the given passwords will be
the ones that will need to be used.

To avoid problems, use it with an owner password set and the SRK having
the well known password. SRK_PASSWORD=  [empty] corresponds to the well
known SRK password of 20 zero bytes.

```
  docker run -ti --env USE_SWTPM= --env OWNER_PASSWORD=ooo --env SRK_PASSWORD= \
   --device=/dev/tpm0:/dev/tpm0 --rm jwt-sidecar \
   gen-jwt.sh --iss example-issuer --aud foo,bar --claims=email:foo@google.com,dead:beef
```

To run the Flask server:

```
  docker build -t jwt-sidecar .

  # run with swtpm:
  docker run -d --name jwt -p 8080:5000 \
   --env USE_SWTPM=1 --env OWNER_PASSWORD=ooo --env SRK_PASSWORD= \
   jwt-sidecar /usr/local/bin/run-tpm-server.sh

  # run with hwtpm (see note above!!)
  docker run -d --name jwt -p 8080:5000 \
   --env USE_SWTPM=  --env OWNER_PASSWORD=ooo --env SRK_PASSWORD= \
   --device=/dev/tpm0:/dev/tpm0 \
   jwt-sidecar /usr/local/bin/run-tpm-server.sh

```

Then test from another console:

```
curl "localhost:8080/getJWT?a=b&kjljkl=klj&bb=ccc&images=img1,img2,img3"
```
