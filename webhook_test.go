package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
	"testing"

	corev1 "k8s.io/api/core/v1"

	"github.com/nsf/jsondiff"
	ctiv1 "github.ibm.com/kompass/ti-keyrelease/pkg/apis/cti/v1"
	"k8s.io/api/admission/v1beta1"
)

var pod corev1.Pod
var admissionRequest v1beta1.AdmissionRequest
var admissionResponse v1beta1.AdmissionResponse
var admissionReview v1beta1.AdmissionReview

func init() {

	// Uncomment out the code below to display messages from "glog"
	flag.Set("alsologtostderr", fmt.Sprintf("%t", true))
	var logLevel string
	flag.StringVar(&logLevel, "logLevel", "5", "test")
	flag.Parse()
	flag.Lookup("v").Value.Set(logLevel)
	fmt.Println("Argument '-logLevel' is ", logLevel)

	// load K8s objects and unmarshal them to test the API format
	pod = getFakePod()
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

// TestLoadInitFile - tests loadInitContainerConfig method from webhook.go. Validates the output
func TestLoadInitFile(t *testing.T) {
	icc, err := loadInitContainerConfig("tests/ConfigFile.yaml")
	if err != nil {
		t.Errorf("Error loading InitContainerConfig %v", err)
		return
	}

	err = validateResult(icc, "tests/ExpectInitContainerConfig.json")
	if err != nil {
		t.Errorf("Result failed: %v", err)
		return
	}
	t.Logf("Results match expections")
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

// TestMutateInitialization - tests the results of calling `mutateInitialization` in webhook
func TestMutateInitialization(t *testing.T) {

	ret := ctiv1.ClusterTI{
		Info: ctiv1.ClusterTISpec{
			ClusterName:   "testCluster",
			ClusterRegion: "testRegion",
		},
	}
	clInfo := newCigKubeTest(ret)

	icc, err := loadInitContainerConfig("tests/ConfigFile.yaml")
	if err != nil {
		t.Errorf("Error loading InitContainerConfig %v", err)
		return
	}

	whsvr := &WebhookServer{
		initcontainerConfig: icc,
		server:              &http.Server{},
		clusterInfo:         clInfo,
	}

	// get test result of running mutateInitialization method:
	result, err := whsvr.mutateInitialization(pod, &admissionRequest)
	if err != nil {
		t.Errorf("Error executing mutateInitialization %v", err)
		return
	}

	err = validateResult(result, "tests/ExpectMutateInit.json")
	if err != nil {
		t.Errorf("Result failed: %v", err)
		return
	}
	t.Logf("Results match expections")
}

func getContentOfTheFile(file string) string {
	dat, err := ioutil.ReadFile(file)
	if err != nil {
		panic(err)
	}
	return string(dat)
}

func getFakePod() corev1.Pod {
	s := getContentOfTheFile("tests/FakePod.json")
	pod := corev1.Pod{}
	json.Unmarshal([]byte(s), &pod)
	return pod
}

func getFakeAdmissionRequest() v1beta1.AdmissionRequest {
	s := getContentOfTheFile("tests/FakeAdmissionRequest.json")
	ar := v1beta1.AdmissionRequest{}
	json.Unmarshal([]byte(s), &ar)
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
	json.Unmarshal([]byte(s), &ar)
	return ar
}

func getInitContainerConfig() InitContainerConfig {
	s := getContentOfTheFile("tests/FakeInitContainerConfig.json")
	obj := InitContainerConfig{}
	json.Unmarshal([]byte(s), &obj)
	return obj
}

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
		fmt.Printf("Results match expections: %v", diff)
		return nil
	}
	return fmt.Errorf("Results do not match expections: %v %v", diff, text)
}
