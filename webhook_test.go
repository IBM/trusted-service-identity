package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"testing"

	corev1 "k8s.io/api/core/v1"

	ctiv1 "github.com/IBM/trusted-service-identity/pkg/apis/cti/v1"
	"github.com/nsf/jsondiff"
	"k8s.io/api/admission/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

/*
	In order to generate a new content of the Fake and Expect files,
	uncomment out the corresponding `logJSON`statements in webhook.go
	Then re-run the tests
*/

//var pod corev1.Pod
var admissionRequest v1beta1.AdmissionRequest

const (
	SUCCESS   = "Testing %s successful"
	ERROR     = "ERROR: Testing %s failed"
	ERRORWITH = "ERROR: Testing %s failed with %s"
)

func init() {

	// Uncomment out the code below to display messages from "glog"
	//flag.Set("alsologtostderr", fmt.Sprintf("%t", true))
	//var logLevel string
	//flag.StringVar(&logLevel, "logLevel", "5", "test")
	//flag.Parse()
	// //flag.Lookup("v").Value.Set(logLevel)
	// fmt.Println("Argument '-logLevel' is ", logLevel)

	// load K8s objects and unmarshal them to test the API format
	//pod = getFakePod("tests/FakePod.json")
	admissionRequest = getFakeAdmissionRequest()
}

type cigKubeTest struct {
	ret ctiv1.ClusterTI
}

func newCigKubeTest(ret ctiv1.ClusterTI) *cigKubeTest {
	return &cigKubeTest{ret}
}

// GetClusterTI implements method for ClusterInfoGetter interface, to be used
// in testing
func (ck *cigKubeTest) GetClusterTI(namespace, name string) (ctiv1.ClusterTI, error) {
	return ck.ret, nil
}

// TestLoadInitFile - tests loadtsiMutateConfig method from webhook.go. Validates the output
func TestLoadConfigFile(t *testing.T) {
	testName := "load config file"
	icc, err := loadtsiMutateConfig("tests/ConfigFile.yaml")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}

	err = validateResult(icc, "tests/ExpectTsiMutateConfig.json")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}
	t.Logf(SUCCESS, testName)
}

// TestPseudoUUID - testing function to generate UUIDs
// func TestPseudoUUID(t *testing.T) {
// 	uuid, err := pseudoUUID()
// 	if err != nil {
// 		t.Errorf("Error obtaining pseudo_uuid %v", err)
// 		return
// 	}
// 	t.Logf("UUID: %v", uuid)
//}

func TestIsSafe(t *testing.T) {
	// test 1 Create OK
	testName := "CREATE with safe pod"
	tpod := getFakePod("tests/FakeIsSafeCreateOK.json")
	err := isSafe(&tpod, "CREATE")
	if err == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	// test 2 Create Error
	testName = "CREATE with non-safe pod"
	tpod = getFakePod("tests/FakeIsSafeCreateError.json")
	err = isSafe(&tpod, "CREATE")
	if err != nil && errors.Is(err, ErrHostpathSocket) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Fatalf(ERROR, testName)
	}

	// test 3 Update OK
	testName = "UPDATE with safe pod"
	tpod = getFakePod("tests/FakeIsSafeUpdateOK.json")
	err = isSafe(&tpod, "UPDATE")
	if err == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	// test 4 Update Error
	testName = "UPDATE with non-safe pod"
	tpod = getFakePod("tests/FakeIsSafeUpdateError.json")
	err = isSafe(&tpod, "UPDATE")
	if err != nil && errors.Is(err, ErrSidecarImg) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Fatalf(ERROR, testName)
	}

}

func TestIsProtectedNamespace(t *testing.T) {

	// tsiNamespce is protected, mutating containers cannot be created
	tsiNamespace := "trusted-identity"
	protectedList := []string{"kube-system", "kube-public", tsiNamespace}

	testName := "protected namespace"
	meta := getFakeMetadata("tests/FakeMutationRequired.json")
	meta.Namespace = tsiNamespace

	protected := isProtectedNamespace(protectedList, &meta)
	if protected {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	// using non-protected namespace
	testName = "non-protected namespace"
	ns := "test"
	meta = getFakeMetadata("tests/FakeMutationRequired.json")
	//meta.Namespace = ns
	meta.Namespace = ns

	protected = isProtectedNamespace(protectedList, &meta)
	if protected {
		t.Errorf(ERROR, testName)
	} else {
		t.Logf(SUCCESS, testName)
	}
}

func TestMutationRequired(t *testing.T) {

	testNs := "test"
	tsiNs := "trusted-identity"
	protectedList := []string{"kube-system", "kube-public", tsiNs}

	// testing if pod should be mutated
	tpod := getFakePod("tests/FakePod.json")

	testName := "mutation required in test namespace"
	tpod.ObjectMeta.Namespace = testNs
	required, err := mutationRequired(protectedList, &tpod, "CREATE")
	if required && err == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "mutation required in protected namespace"
	tpod.ObjectMeta.Namespace = tsiNs
	required, err = mutationRequired(protectedList, &tpod, "CREATE")
	if required && err != nil && errors.Is(err, ErrProtectedNs) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	tpod = getFakePod("tests/FakePodNM.json")
	testName = "mutation not required in test namespace"
	tpod.ObjectMeta.Namespace = testNs
	required, err = mutationRequired(protectedList, &tpod, "CREATE")
	if !required && err == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	tpod = getFakePod("tests/FakePodNM.json")
	testName = "mutation not required in protected namespace"
	tpod.ObjectMeta.Namespace = tsiNs
	required, err = mutationRequired(protectedList, &tpod, "CREATE")
	if !required && err == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "mutation required with Hostpath in test namespace"
	tpod = getFakePod("tests/FakePodVO.json")
	tpod.ObjectMeta.Namespace = testNs
	required, err = mutationRequired(protectedList, &tpod, "CREATE")
	if required && err != nil && errors.Is(err, ErrHostpathSocket) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "mutation required with Hostpath in protected namespace"
	tpod = getFakePod("tests/FakePodVO.json")
	tpod.ObjectMeta.Namespace = tsiNs
	required, err = mutationRequired(protectedList, &tpod, "CREATE")
	if required && err != nil && (errors.Is(err, ErrHostpathSocket) || errors.Is(err, ErrProtectedNs)) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "mutation not required with Hostpath in test namespace"
	tpod = getFakePod("tests/FakePodNM-VO.json")
	tpod.ObjectMeta.Namespace = testNs
	required, err = mutationRequired(protectedList, &tpod, "CREATE")
	if !required && err != nil && errors.Is(err, ErrHostpathSocket) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "mutation not required with Hostpath in protected namespace"
	tpod = getFakePod("tests/FakePodNM-VO.json")
	tpod.ObjectMeta.Namespace = tsiNs
	required, err = mutationRequired(protectedList, &tpod, "CREATE")
	if !required && err == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "update in test namespace"
	tpod = getFakePod("tests/FakePodUpdate.json")
	tpod.ObjectMeta.Namespace = testNs
	required, err = mutationRequired(protectedList, &tpod, "UPDATE")
	if required && err == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "update sidecar image in test namespace"
	tpod = getFakePod("tests/FakePodUpdateErr.json")
	tpod.ObjectMeta.Namespace = testNs
	required, err = mutationRequired(protectedList, &tpod, "UPDATE")
	if required && err != nil && errors.Is(err, ErrSidecarImg) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}
}

func TestUpdateAnnotation(t *testing.T) {

	// test 1, standard create
	testName := "update standard annotations"
	target := getFakeAnnotation("tests/FakeUpdateAnnotationTarget.json")
	added := getFakeAnnotation("tests/FakeUpdateAnnotation.json")
	result := updateAnnotation(target, added)

	err := validateResult(result, "tests/ExpectUpdateAnnotation.json")
	if err != nil {
		t.Fatalf(ERROR, testName)
		return
	}
	t.Logf(SUCCESS, testName)

	// test 2, UPDATE to force incorrect annotations
	testName = "update error annotations"
	target = getFakeAnnotation("tests/FakeUpdateAnnotationTargetErr.json")
	added = getFakeAnnotation("tests/FakeUpdateAnnotation2.json")
	result = updateAnnotation(target, added)

	err = validateResult(result, "tests/ExpectUpdateAnnotation2.json")
	if err != nil {
		t.Errorf(ERROR, testName)
		return
	}
	t.Logf(SUCCESS, testName)

}

func TestAddContainer(t *testing.T) {
	testName := "add container"
	target := getFakeContainers("tests/FakeAddContainerTarget.json")
	add := getFakeContainers("tests/FakeAddContainer.json")
	result := addContainer(target, add, "/spec/containers")

	err := validateResult(result, "tests/ExpectAddContainer.json")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}
	t.Logf(SUCCESS, testName)
}

func TestPrependContainer(t *testing.T) {
	testName := "prepend container"
	target := getFakeContainers("tests/FakePrependContainerTarget.json")
	add := getFakeContainers("tests/FakePrependContainer.json")
	result := prependContainer(target, add, "/spec/initContainers")

	err := validateResult(result, "tests/ExpectPrependContainer.json")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}
	t.Logf(SUCCESS, testName)
}

func TestAddVolume(t *testing.T) {
	testName := "add volume"
	target := getFakeVolume("tests/FakeAddVolumeTarget.json")
	add := getFakeVolume("tests/FakeAddVolume.json")
	result := addVolume(target, add, "/spec/volumes")

	err := validateResult(result, "tests/ExpectAddVolume.json")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}
	t.Logf(SUCCESS, testName)
}

// TestMutate - tests the results of calling `mutateInitialization`
// and `mutate` in the webhook
func TestMutate(t *testing.T) {

	testName := "load config file"
	icc, err := loadtsiMutateConfig("tests/ConfigFile.yaml")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}

	err = validateResult(icc, "tests/ExpectTsiMutateConfig.json")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	} else {
		t.Logf(SUCCESS, testName)
	}

	testName = "mutate initialization"
	ret := ctiv1.ClusterTI{
		Info: ctiv1.ClusterTISpec{
			ClusterName:   "testCluster",
			ClusterRegion: "testRegion",
		},
	}
	clInfo := newCigKubeTest(ret)

	tsiNamespace := "trusted-identity"
	protectedList := []string{"kube-system", "kube-public", tsiNamespace}

	whsvr := &WebhookServer{
		tsiMutateConfig:     icc,
		server:              &http.Server{},
		clusterInfo:         clInfo,
		protectedNamespaces: protectedList,
	}

	fpod := getFakePod("tests/FakePod.json")
	// get test result of running mutateInitialization method:
	result, err := whsvr.mutateInitialization(fpod, &admissionRequest)
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}

	err = validateResult(result, "tests/ExpectMutateInit2.json")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}
	t.Logf(SUCCESS, testName)

	testName = "mutate in protected namespace"
	ar := getFakeAdmissionReview("tests/FakeAdmissionReview.json")

	req := ar.Request
	var pod corev1.Pod
	if err := json.Unmarshal(req.Object.Raw, &pod); err != nil {
		t.Errorf("Could not unmarshal raw object: %v", err)
		t.Errorf(ERRORWITH, testName, err)
	}

	ar.Request.Namespace = "trusted-identity"
	admRsp := whsvr.mutate(&ar)
	if admRsp.Allowed == false && string(admRsp.Result.Reason) == MsgNoCreate && string(admRsp.Result.Message) == MsgProtectNs && admRsp.Patch == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "mutate in test namespace"
	ar.Request.Namespace = "test"
	admRsp = whsvr.mutate(&ar)
	if admRsp.Allowed == true && admRsp.Patch != nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "update in test namespace"
	ar.Request.Operation = "UPDATE"
	admRsp = whsvr.mutate(&ar)
	if admRsp.Allowed == true && admRsp.Patch != nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "update with wrong sidecar image in test namespace"
	ar = getFakeAdmissionReview("tests/FakeAdmissionReviewUpdateErr.json")
	ar.Request.Operation = "UPDATE"
	admRsp = whsvr.mutate(&ar)
	if admRsp.Allowed == false && string(admRsp.Result.Reason) == MsgNoCreate && string(admRsp.Result.Message) == MsgSidecarImg && admRsp.Patch == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "create pod with hostPath access in test namespace"
	ar = getFakeAdmissionReview("tests/FakeAdmissionReviewErr.json")
	admRsp = whsvr.mutate(&ar)
	if admRsp.Allowed == false && string(admRsp.Result.Reason) == MsgNoCreate && string(admRsp.Result.Message) == MsgHostPath && admRsp.Patch == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "no mutation in TSI namespace"
	ar = getFakeAdmissionReview("tests/FakeAdmissionReviewNM.json")
	admRsp = whsvr.mutate(&ar)
	if admRsp.Allowed == true && admRsp.Patch == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	testName = "no mutation in test namespace"
	ar.Request.Namespace = "test"
	admRsp = whsvr.mutate(&ar)
	if admRsp.Allowed == true && admRsp.Patch == nil {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

}

func getContentOfTheFile(filePath string) string {
	dat, err := ioutil.ReadFile(filePath)
	if err != nil {
		panic(err)
	}
	return string(dat)
}

func getFakePod(filePath string) corev1.Pod {
	s := getContentOfTheFile(filePath)
	pod := corev1.Pod{}
	err := json.Unmarshal([]byte(s), &pod)
	if err != nil {
		panic(err)
	}
	return pod
}

func getFakeContainers(filePath string) []corev1.Container {
	s := getContentOfTheFile(filePath)
	c := []corev1.Container{}
	err := json.Unmarshal([]byte(s), &c)
	if err != nil {
		panic(err)
	}
	return c
}

func getFakeVolume(filePath string) []corev1.Volume {
	s := getContentOfTheFile(filePath)
	vol := []corev1.Volume{}
	err := json.Unmarshal([]byte(s), &vol)
	if err != nil {
		panic(err)
	}
	return vol
}

func getFakeVolumeMount(filePath string) []corev1.VolumeMount {
	s := getContentOfTheFile(filePath)
	vol := []corev1.VolumeMount{}
	err := json.Unmarshal([]byte(s), &vol)
	if err != nil {
		panic(err)
	}
	return vol
}

func getFakeMetadata(filePath string) metav1.ObjectMeta {
	s := getContentOfTheFile(filePath)
	meta := metav1.ObjectMeta{}
	err := json.Unmarshal([]byte(s), &meta)
	if err != nil {
		panic(err)
	}
	return meta
}

func getFakeAnnotation(filePath string) map[string]string {
	s := getContentOfTheFile(filePath)
	ann := make(map[string]string)
	err := json.Unmarshal([]byte(s), &ann)
	if err != nil {
		panic(err)
	}
	return ann
}

func getFakeAdmissionRequest() v1beta1.AdmissionRequest {
	s := getContentOfTheFile("tests/FakeAdmissionRequest.json")
	ar := v1beta1.AdmissionRequest{}
	err := json.Unmarshal([]byte(s), &ar)
	if err != nil {
		panic(err)
	}
	return ar
}

func getFakeAdmissionResponse() v1beta1.AdmissionResponse {
	s := getContentOfTheFile("tests/FakeAdmissionResponse.json")
	ar := v1beta1.AdmissionResponse{}
	json.Unmarshal([]byte(s), &ar)
	return ar
}

func getFakeAdmissionReview(filePath string) v1beta1.AdmissionReview {
	s := getContentOfTheFile(filePath)
	ar := v1beta1.AdmissionReview{}
	err := json.Unmarshal([]byte(s), &ar)
	if err != nil {
		panic(err)
	}
	return ar
}

func getTsiMutateConfig() tsiMutateConfig {
	s := getContentOfTheFile("tests/FakeTsiMutateConfig.json")
	obj := tsiMutateConfig{}
	err := json.Unmarshal([]byte(s), &obj)
	if err != nil {
		panic(err)
	}
	return obj
}

// func printObject(r interface{}) {
// 	// marshal the object to []byte for comparison
// 	result, err := json.Marshal(r)
// 	if err != nil {
// 		t.errorF("%v", err)
// 		//return err
// 	}
//
// }

func validateResult(r interface{}, expectedFile string) error {

	// marshal the object to []byte for comparison
	result, err := json.Marshal(r)
	if err != nil {
		return err
	}

	// get the exepected result from a file
	exp, err := ioutil.ReadFile(expectedFile)
	if err != nil {
		return err
	}

	// Execute JSON diff on both byte representations of JSON
	// when using DefaultHTMLOptions, `text` can be treated as
	// HTML with <pre> to show differences with colors
	opts := jsondiff.DefaultHTMLOptions()
	diff, text := jsondiff.Compare(result, exp, &opts)
	if diff == jsondiff.FullMatch {
		// fmt.Printf("Results match expections: %v", diff)
		return nil
	}
	return fmt.Errorf("Results do not match expections. diff: %v text: %v", diff, text)
}
