#!/bin/bash

TESTS="../tests"
SLEEP=10
EXAMPLES="../examples"

# check if webhook running in debug mode
webhoook_cmd="kubectl -n trusted-identity exec -it $(kubectl -n trusted-identity get po | grep mutate-webhook| awk '{print $1}') -- "
pod_cmd="kubectl -n test"

$webhoook_cmd cat /etc/webhook/config/tsiMutateConfig.yaml > ${TESTS}/ConfigFile.yaml
$webhoook_cmd cat /tmp/ExpectTsiMutateConfig.json > ${TESTS}/ExpectTsiMutateConfig.json
# kk exec -it $(kk get po | grep mutate-webhook| awk '{print $1}') -- cat /etc/webhook/config/tsiMutateConfig.yaml > ${TESTS}/ConfigFile.yaml
# Add to  ExpectTsiMutateConfig.json missing annotations as:
# "admission.trusted.identity/tsi-cluster-name": <span style="background-color: #fcff7f">"testCluster" => "minikube"</span>,
# "admission.trusted.identity/tsi-images": <span style="background-color: #fcff7f">"" => "ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4"</span>,
# "admission.trusted.identity/tsi-region": <span style="background-color: #fcff7f">"testRegion" => "eu-de"</span>

$pod_cmd create -f ${EXAMPLES}/myubuntu.yaml
# if error delete and recreate
sleep $SLEEP
$webhoook_cmd cat /tmp/FakeAdmissionReview.json > ${TESTS}/FakeAdmissionReview.json
$webhoook_cmd cat /tmp/ExpectMutateInit.json > ${TESTS}/ExpectMutateInit.json
$webhoook_cmd cat /tmp/FakeIsSafeX.json > ${TESTS}/FakeIsSafeCreateOK.json
$webhoook_cmd cat /tmp/FakePod.json > ${TESTS}/FakePod.json
$webhoook_cmd cat /tmp/FakeMutationRequired.json > ${TESTS}/FakeMutationRequired.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotationTarget.json > ${TESTS}/FakeUpdateAnnotationTarget.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotation.json > ${TESTS}/FakeUpdateAnnotation.json
$webhoook_cmd cat /tmp/ExpectUpdateAnnotation.json > ${TESTS}/ExpectUpdateAnnotation.json
sed 's/}/,/g' ${TESTS}/FakeUpdateAnnotation.json > ${TESTS}/FakeUpdateAnnotationError.json
cat <<EOT >> ${TESTS}/FakeUpdateAnnotationError.json
    "tsi.secrets": "- tsi.secret/name: \"mysecret1\"\n  tsi.secret/role: \"tsi-role-rcni\"\n  tsi.secret/vault-path: \"secret/tsi-rcni\"\n  tsi.secret/local-path: \"mysecrets/myubuntu-mysecret1\"\n- tsi.secret/name: \"mysecret2.json\"\n  tsi.secret/role: \"tsi-role-rcni\"\n  tsi.secret/vault-path: \"secret/tsi-r\"\n  tsi.secret/local-path: \"mysecrets/myubuntu-mysecret2\"\n- tsi.secret/name: \"password\"\n  tsi.secret/role: \"tsi-role-rcni\"\n  tsi.secret/vault-path: \"secret/tsi-r\"\n  tsi.secret/local-path: \"mysecrets/myubuntu-passwords\"\n- tsi.secret/name: \"invalid\"\n  tsi.secret/role: \"tsi-role-rcni\"\n  tsi.secret/vault-path: \"secret/tsi-rcni\"\n  tsi.secret/local-path: \"mysecrets/myubuntu-invalid\"\n- tsi.secret/name: \"non-existing\"\n  tsi.secret/role: \"tsi-role-rcni\"\n  tsi.secret/vault-path: \"secret/nothing\"\n  tsi.secret/local-path: \"mysecrets/non-existing\"\n"
}
EOT
sed 's/ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4/ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4,trustedseriviceidentity\/ti-jwt-sidecar:v1.5/g' ${TESTS}/FakeUpdateAnnotation.json > ${TESTS}/FakeUpdateAnnotation2.json

$webhoook_cmd cat /tmp/FakeAddContainerTarget.json > ${TESTS}/FakeAddContainerTarget.json
$webhoook_cmd cat /tmp/FakeAddContainer.json > ${TESTS}/FakeAddContainer.json
$webhoook_cmd cat /tmp/ExpectAddContainer.json > ${TESTS}/ExpectAddContainer.json
$webhoook_cmd cat /tmp/FakeAddVolumeTarget.json > ${TESTS}/FakeAddVolumeTarget.json
$webhoook_cmd cat /tmp/FakeAddVolume.json > ${TESTS}/FakeAddVolume.json
$webhoook_cmd cat /tmp/ExpectAddVolume.json > ${TESTS}/ExpectAddVolume.json
$webhoook_cmd cat /tmp/FakeAddVolumeMountTarget.json > ${TESTS}/FakeAddVolumeMountTarget.json
$webhoook_cmd cat /tmp/FakeAddVolumeMount.json > ${TESTS}/FakeAddVolumeMount.json
$webhoook_cmd cat /tmp/ExpectAddVolumeMount.json > ${TESTS}/ExpectAddVolumeMount.json
$webhoook_cmd cat /tmp/FakeAdmissionRequest.json > ${TESTS}/FakeAdmissionRequest.json
$webhoook_cmd cat /tmp/FakeAdmissionResponse.json > ${TESTS}/FakeAdmissionResponse.json
$webhoook_cmd cat /tmp/FakeTsiMutateConfig.json > ${TESTS}/FakeTsiMutateConfig.json

sed 's/inject": "true"/inject": "false"/g' ../tests/FakePod.json > ../tests/FakePodNM.json

# copy FakeIsSafeCreateOK.json add hostpath --> FakeIsSafeCreateError.json

$pod_cmd get po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -ojson > ${TESTS}/FakeIsSafeUpdate.json
sed 's/mysecret1/mysecret1xxx/g' ${TESTS}/FakeIsSafeUpdate.json > ${TESTS}/FakeIsSafeUpdateOK.json
sed 's/trustedseriviceidentity\/ti-jwt-sidecar/ubuntu/g' ${TESTS}/FakeIsSafeUpdate.json  > ${TESTS}/FakeIsSafeUpdateError.json
# kubectl patch pod valid-pod -p '{"spec":{"containers":[{"name":"kubernetes-serve-hostname","image":"new image"}]}}'

$pod_cmd apply -f ${TESTS}/FakeIsSafeUpdateOK.json
$pod_cmd get po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -ojson > ${TESTS}/FakePodUpdate.json
# FakeIsSafeUpdateOK.json:
# k get po myubuntu-xxx -o yaml
# k get po  myubuntu-6d5c486b66-94czv -ojson > ../tests/FakeIsSafeUpdateOK.json
# update secret annotation xxx
sed 's/mysecret1/mysecret1xxx/g' ${TESTS}/FakeIsSafeUpdateOK.json > ${TESTS}/FakePodUpdate.json
sed 's/trustedseriviceidentity/badplace/g' ${TESTS}/FakePodUpdate.json > ${TESTS}/FakePodUpdateErr.json

$pod_cmd patch pod $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -p '{"spec":{"containers":[{"name":"jwt-sidecar","image":"ubuntu"}]}}'
$webhoook_cmd cat /tmp/FakeAdmissionReview.json > ${TESTS}/FakeAdmissionReviewUpdateErr.json

# '{"metadata":{"annotations"}:{"admission.trusted.identity/tsi-cluster-name": "minikubexxx"}}'

# patch the container by changing the protected annotations:
$pod_cmd patch po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -p '{"metadata":{"annotations":{"admission.trusted.identity/tsi-cluster-name": "minikubexxx"}}}'
$webhoook_cmd cat /tmp/FakeUpdateAnnotationTarget.json > ${TESTS}/FakeUpdateAnnotationTargetErr.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotation.json > ${TESTS}/FakeUpdateAnnotation2.json
$webhoook_cmd cat /tmp/ExpectUpdateAnnotation.json > ${TESTS}/ExpectUpdateAnnotation2.json


# FakeIsSafeCreateError.json:
# delete myubuntu.yaml
# k create -f myubuntuErr1.yaml
# from kk logs tsi-mutate-webhook-deployment-84c686dc65-xsh2f
#  webhook.go:729] JSON for FakePod.json:
$pod_cmd delete -f ${EXAMPLES}/myubuntu.yaml

$pod_cmd create -f ${EXAMPLES}/myubuntuErr.yaml; sleep $SLEEP
$webhoook_cmd cat /tmp/FakePod.json > ${TESTS}/FakePodVO.json
$webhoook_cmd cat /tmp/FakeAdmissionReview.json > ${TESTS}/FakeAdmissionReviewErr.json
sed 's/"admission.trusted.identity\/inject": "true"/"admission.trusted.identity\/inject": "false"/g' ${TESTS}/FakePodVO.json  > ${TESTS}/FakePodNM-VO.json
$pod_cmd delete -f ${EXAMPLES}/myubuntuErr.yaml; sleep $SLEEP

$pod_cmd create -f ${EXAMPLES}/myubuntuErr1.yaml; sleep $SLEEP
$webhoook_cmd cat /tmp/FakePod.json > ${TESTS}/FakeIsSafeCreateError.json

# create a pod with initContainer
$pod_cmd create -f ${EXAMPLES}/myubuntu-initC.yaml; sleep $SLEEP
$webhoook_cmd cat /tmp/FakePrependContainerTarget.json > ${TESTS}/FakePrependContainerTarget.json
$webhoook_cmd cat /tmp/FakePrependContainer.json > ${TESTS}/FakePrependContainer.json
$webhoook_cmd cat /tmp/ExpectPrependContainer.json > ${TESTS}/ExpectPrependContainer.json
cat ${TESTS}/ExpectMutateInit.json | sed 's/"minikube"/"testCluster"/g' | sed 's/"eu-de"/"testRegion"/g' > ${TESTS}/ExpectMutateInit2.json

# create a pod without mutation:
$pod_cmd create -f ${EXAMPLES}/myubuntuNM.yaml; sleep $SLEEP
$webhoook_cmd cat /tmp/FakeAdmissionReview.json > ${TESTS}/FakeAdmissionReviewNM.json

# cleanup it all:
$pod_cmd delete -f ${EXAMPLES}/myubuntuErr1.yaml
$pod_cmd delete -f ${EXAMPLES}/myubuntu-initC.yaml
$pod_cmd delete -f ${EXAMPLES}/myubuntuNM.yaml
