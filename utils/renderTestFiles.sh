#!/bin/bash

TESTS="../tests"

# check if webhook running in debug mode
webhoook_cmd="kubectl -n trusted-identity exec -it $(kubectl -n trusted-identity get po | grep mutate-webhook| awk '{print $1}') -- "
pod_cmd="kubectl -n test"

$webhoook_cmd cat /etc/webhook/config/tsiMutateConfig.yaml > $TESTS/ConfigFile.yaml
$webhoook_cmd cat /tmp/ExpectTsiMutateConfig.json > $TESTS/ExpectTsiMutateConfig.json
# kk exec -it $(kk get po | grep mutate-webhook| awk '{print $1}') -- cat /etc/webhook/config/tsiMutateConfig.yaml > $TESTS/ConfigFile.yaml
# Add to  ExpectTsiMutateConfig.json missing annotations as:
# "admission.trusted.identity/tsi-cluster-name": <span style="background-color: #fcff7f">"testCluster" => "minikube"</span>,
# "admission.trusted.identity/tsi-images": <span style="background-color: #fcff7f">"" => "ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4"</span>,
# "admission.trusted.identity/tsi-region": <span style="background-color: #fcff7f">"testRegion" => "eu-de"</span>

$pod_cmd create -f ../examples/myubuntu.yaml
# if error delete and recreate
sleep 15
$webhoook_cmd cat /tmp/FakeAdmissionReview.json > $TESTS/FakeAdmissionReview.json
$webhoook_cmd cat /tmp/ExpectMutateInit.json > $TESTS/ExpectMutateInit.json
$webhoook_cmd cat /tmp/FakePod.json > $TESTS/FakeIsSafeCreateOK.json
$webhoook_cmd cat /tmp/FakePod.json > $TESTS/FakePod.json
$webhoook_cmd cat /tmp/FakeMutationRequired.json > $TESTS/FakeMutationRequired.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotationTarget.json > $TESTS/FakeUpdateAnnotationTarget.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotation.json > $TESTS/FakeUpdateAnnotation.json
$webhoook_cmd cat /tmp/ExpectUpdateAnnotation.json > $TESTS/ExpectUpdateAnnotation.json
$webhoook_cmd cat /tmp/FakeAddContainerTarget.json > $TESTS/FakeAddContainerTarget.json
$webhoook_cmd cat /tmp/FakeAddContainer.json > $TESTS/FakeAddContainer.json
$webhoook_cmd cat /tmp/ExpectAddContainer.json > $TESTS/ExpectAddContainer.json
$webhoook_cmd cat /tmp/FakeAddVolumeTarget.json > $TESTS/FakeAddVolumeTarget.json
$webhoook_cmd cat /tmp/FakeAddVolume.json > $TESTS/FakeAddVolume.json
$webhoook_cmd cat /tmp/ExpectAddVolume.json > $TESTS/ExpectAddVolume.json
$webhoook_cmd cat /tmp/FakeAddVolumeMountTarget.json > $TESTS/FakeAddVolumeMountTarget.json
$webhoook_cmd cat /tmp/FakeAddVolumeMount.json > $TESTS/FakeAddVolumeMount.json
$webhoook_cmd cat /tmp/ExpectAddVolumeMount.json > $TESTS/ExpectAddVolumeMount.json
$webhoook_cmd cat /tmp/FakeAdmissionRequest.json > $TESTS/FakeAdmissionRequest.json

sed 's/inject": "true"/inject": "false"/g' ../tests/FakePod.json > ../tests/FakePodNM.json

# copy FakeIsSafeCreateOK.json add hostpath --> FakeIsSafeCreateError.json

$pod_cmd get po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -ojson > $TESTS/FakeIsSafeUpdate.json
sed 's/mysecret1/mysecret1xxx/g' $TESTS/FakeIsSafeUpdate.json > $TESTS/FakeIsSafeUpdateOK.json
sed 's/trustedseriviceidentity/badplace/g' $TESTS/FakeIsSafeUpdateOK.json  > $TESTS/FakeIsSafeUpdateError.json
# kubectl patch pod valid-pod -p '{"spec":{"containers":[{"name":"kubernetes-serve-hostname","image":"new image"}]}}'

$pod_cmd apply -f $TESTS/FakeIsSafeUpdateOK.json
$pod_cmd get po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -ojson > $TESTS/FakePodUpdate.json
# FakeIsSafeUpdateOK.json:
# k get po myubuntu-xxx -o yaml
# k get po  myubuntu-6d5c486b66-94czv -ojson > ../tests/FakeIsSafeUpdateOK.json
# update secret annotation xxx
sed 's/mysecret1/mysecret1xxx/g' $TESTS/FakeIsSafeUpdateOK.json > $TESTS/FakePodUpdate.json
sed 's/trustedseriviceidentity/badplace/g' $TESTS/FakePodUpdate.json > $TESTS/FakePodUpdateErr.json

# FakeIsSafeCreateError.json:
# delete myubuntu.yaml
# k create -f myubuntuErr1.yaml
# from kk logs tsi-mutate-webhook-deployment-84c686dc65-xsh2f
#  webhook.go:729] JSON for FakePod.json:
$pod_cmd delete -f ../examples/myubuntu.yaml
$pod_cmd create -f ../examples/myubuntuErr1.yaml; sleep 15
$pod_cmd exec -it $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -ojson > $TESTS/FakeIsSafeCreateError.json
$pod_cmd delete -f ../examples/myubuntuErr1.yaml; sleep 15

$pod_cmd create -f ../examples/myubuntu-initC.yaml; sleep 15
$webhoook_cmd cat /tmp/FakePrependContainerTarget.json > $TESTS/FakePrependContainerTarget.json
$webhoook_cmd cat /tmp/FakePrependContainer.json > $TESTS/FakePrependContainer.json
$webhoook_cmd cat /tmp/ExpectPrependContainer.json > $TESTS/ExpectPrependContainer.json
$pod_cmd delete -f ../examples/myubuntu-initC.yaml

exit 0



$webhoook_cmd cat /tmp/ > $TESTS/
$webhoook_cmd cat /tmp/ > $TESTS/



FakePodVO.json
copy FakePod.json and inject hostPath

"volumes": [
    {
        "name": "default-token-wp8ht",
        "secret": {
            "secretName": "default-token-wp8ht"
        }
    },
    {
        "hostPath": {
            "path": "/var/tsi-secure/sockets",
            "type": "Directory"
        },
        "name": "tsi-sockets"
    }
],

FakePodNMVO.json
copy FakePodNM.json and inject hostPath


 [
