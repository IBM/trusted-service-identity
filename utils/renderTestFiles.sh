#!/bin/bash
TESTS="$(dirname "$0")/../tests"
EXAMPLES="$(dirname "$0")/../examples"
SLEEP=10

# common commands
pod_cmd="kubectl -n test"
id=$(kubectl -n trusted-identity get po | grep mutate-webhook| awk '{print $1}')
webhoook_cmd="kubectl -n trusted-identity exec $id --"

# check if webhook running in debug mode
DEB=$(kubectl -n trusted-identity exec $id -- env | grep DEBUG)
if [ "$DEB" != "DEBUG=true" ]; then
  echo "ERROR: webhook is not running in DEBUG mode. Please enable DEBUG=true"
  exit 1
fi

# cleanup before rendering new files:
rm -rf ${TESTS}
mkdir -p ${TESTS}

$webhoook_cmd cat /etc/webhook/config/tsiMutateConfig.yaml > ${TESTS}/ConfigFile.yaml
$webhoook_cmd cat /tmp/ExpectTsiMutateConfig.json > ${TESTS}/ExpectTsiMutateConfig.json

# start a sample pod
$pod_cmd create -f ${EXAMPLES}/myubuntu.yaml
# if error delete and recreate
if [ "$?" != "0" ]; then
 $pod_cmd delete -f ${EXAMPLES}/myubuntu.yaml
 $pod_cmd create -f ${EXAMPLES}/myubuntu.yaml
fi
sleep $SLEEP

$webhoook_cmd cat /tmp/FakeAdmissionReview.json > ${TESTS}/FakeAdmissionReview.json
$webhoook_cmd cat /tmp/ExpectMutateInit.json > ${TESTS}/ExpectMutateInit.json
$webhoook_cmd cat /tmp/FakeIsSafeX.json > ${TESTS}/FakeIsSafeCreateOK.json
$webhoook_cmd cat /tmp/FakePod.json > ${TESTS}/FakePod.json
$webhoook_cmd cat /tmp/FakeMutationRequired.json > ${TESTS}/FakeMutationRequired.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotationTarget.json > ${TESTS}/FakeUpdateAnnotationTarget.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotation.json > ${TESTS}/FakeUpdateAnnotation.json
$webhoook_cmd cat /tmp/ExpectUpdateAnnotation.json > ${TESTS}/ExpectUpdateAnnotation.json
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

sed 's/inject": "true"/inject": "false"/g' ${TESTS}/FakePod.json > ${TESTS}/FakePodNM.json

$pod_cmd get po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -ojson > ${TESTS}/FakeIsSafeUpdate.json
sed 's/mysecret1/mysecret1xxx/g' ${TESTS}/FakeIsSafeUpdate.json > ${TESTS}/FakeIsSafeUpdateOK.json
sed 's/tsidentity\/ti-jwt-sidecar/ubuntu/g' ${TESTS}/FakeIsSafeUpdate.json  > ${TESTS}/FakeIsSafeUpdateError.json
# kubectl patch pod valid-pod -p '{"spec":{"containers":[{"name":"kubernetes-serve-hostname","image":"new image"}]}}'

$pod_cmd apply -f ${TESTS}/FakeIsSafeUpdateOK.json
$pod_cmd get po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -ojson > ${TESTS}/FakePodUpdate.json
sed 's/mysecret1/mysecret1xxx/g' ${TESTS}/FakeIsSafeUpdateOK.json > ${TESTS}/FakePodUpdate.json
sed 's/tsidentity/badplace/g' ${TESTS}/FakePodUpdate.json > ${TESTS}/FakePodUpdateErr.json

$pod_cmd patch pod $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -p '{"spec":{"containers":[{"name":"jwt-sidecar","image":"ubuntu"}]}}'
$webhoook_cmd cat /tmp/FakeAdmissionReview.json > ${TESTS}/FakeAdmissionReviewUpdateErr.json

# patch the container by changing the protected annotations:
$pod_cmd patch po $($pod_cmd get po | grep "myubuntu-" | awk '{print $1}') -p '{"metadata":{"annotations":{"admission.trusted.identity/tsi-cluster-name": "minikubexxx"}}}'
$webhoook_cmd cat /tmp/FakeUpdateAnnotationTarget.json > ${TESTS}/FakeUpdateAnnotationTargetErr.json
$webhoook_cmd cat /tmp/FakeUpdateAnnotation.json > ${TESTS}/FakeUpdateAnnotation2.json
$webhoook_cmd cat /tmp/ExpectUpdateAnnotation.json > ${TESTS}/ExpectUpdateAnnotation2.json

$pod_cmd delete -f ${EXAMPLES}/myubuntu.yaml

# pod requesting mutation with illegal hostpath:
$pod_cmd create -f ${EXAMPLES}/myubuntuErr.yaml; sleep $SLEEP

$webhoook_cmd cat /tmp/FakePod.json > ${TESTS}/FakePodVO.json
$webhoook_cmd cat /tmp/FakeAdmissionReview.json > ${TESTS}/FakeAdmissionReviewErr.json
sed 's/"admission.trusted.identity\/inject": "true"/"admission.trusted.identity\/inject": "false"/g' ${TESTS}/FakePodVO.json  > ${TESTS}/FakePodNM-VO.json
$pod_cmd delete -f ${EXAMPLES}/myubuntuErr.yaml; sleep $SLEEP

# pod without mutation with illegal hostpath:
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
