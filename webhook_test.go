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

var pod corev1.Pod
var admissionRequest v1beta1.AdmissionRequest
var admissionResponse v1beta1.AdmissionResponse
var admissionReview v1beta1.AdmissionReview

const (
	SUCCESS   = "Testing %s successful"
	ERROR     = "Testing %s failed"
	ERRORWITH = "Testing %s failed with %s"
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
	pod = getFakePod("tests/FakePod.json")
	admissionRequest = getFakeAdmissionRequest()
	admissionResponse = getFakeAdmissionResponse()
	admissionReview = getFakeAdmissionReview()
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

func TestMutationRequired(t *testing.T) {

	// testing if pad that should be mutated
	testName := "mutation required"
	meta := getFakeMetadata("tests/FakeMutationRequired.json")
	ignoredNamespaces := []string{"kube-system", "kube-public"}
	if mutationRequired(ignoredNamespaces, &meta) {
		t.Logf(SUCCESS, testName)
		t.Logf("Testing mutating metadata successful")
	} else {
		t.Errorf(ERROR, testName)
		t.Error("Testing mutating metadata failed")
	}

	// testing pod with  "admission.trusted.identity/inject": "false"
	testName = "mutation not required [1]"
	meta = getFakeMetadata("tests/FakeMutationNotRequired1.json")
	ignoredNamespaces = []string{"kube-system", "kube-public"}
	if !mutationRequired(ignoredNamespaces, &meta) {
		t.Logf(SUCCESS, testName)
	} else {
		t.Errorf(ERROR, testName)
	}

	// testing pod with missing  "admission.trusted.identity/inject"
	testName = "mutation not required [2]"
	meta = getFakeMetadata("tests/FakeMutationNotRequired2.json")
	ignoredNamespaces = []string{"kube-system", "kube-public"}
	if !mutationRequired(ignoredNamespaces, &meta) {
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
	target = getFakeAnnotation("tests/FakeUpdateAnnotationError.json")
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

// TestMutateInitialization - tests the results of calling `mutateInitialization` in webhook
func TestMutateInitialization(t *testing.T) {

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

	whsvr := &WebhookServer{
		tsiMutateConfig: icc,
		server:          &http.Server{},
		clusterInfo:     clInfo,
	}

	// get test result of running mutateInitialization method:
	result, err := whsvr.mutateInitialization(pod, &admissionRequest)
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}

	err = validateResult(result, "tests/ExpectMutateInit.json")
	if err != nil {
		t.Errorf(ERRORWITH, testName, err)
		return
	}
	t.Logf(SUCCESS, testName)
}

func getContentOfTheFile(file string) string {
	dat, err := ioutil.ReadFile(file)
	if err != nil {
		panic(err)
	}
	return string(dat)
}

func getFakePod(file string) corev1.Pod {
	s := getContentOfTheFile(file)
	pod := corev1.Pod{}
	err := json.Unmarshal([]byte(s), &pod)
	if err != nil {
		panic(err)
	}
	return pod
}

func getFakeContainers(file string) []corev1.Container {
	s := getContentOfTheFile(file)
	c := []corev1.Container{}
	err := json.Unmarshal([]byte(s), &c)
	if err != nil {
		panic(err)
	}
	return c
}

func getFakeVolume(file string) []corev1.Volume {
	s := getContentOfTheFile(file)
	vol := []corev1.Volume{}
	err := json.Unmarshal([]byte(s), &vol)
	if err != nil {
		panic(err)
	}
	return vol
}

func getFakeVolumeMount(file string) []corev1.VolumeMount {
	s := getContentOfTheFile(file)
	vol := []corev1.VolumeMount{}
	err := json.Unmarshal([]byte(s), &vol)
	if err != nil {
		panic(err)
	}
	return vol
}

func getFakeMetadata(file string) metav1.ObjectMeta {
	s := getContentOfTheFile(file)
	meta := metav1.ObjectMeta{}
	err := json.Unmarshal([]byte(s), &meta)
	if err != nil {
		panic(err)
	}
	return meta
}

func getFakeAnnotation(file string) map[string]string {
	s := getContentOfTheFile(file)
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

func getFakeAdmissionReview() v1beta1.AdmissionReview {
	s := getContentOfTheFile("tests/FakeAdmissionReview.json")
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
