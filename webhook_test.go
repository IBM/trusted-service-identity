package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"

	"github.com/nsf/jsondiff"
	ctiv1 "github.ibm.com/kompass/ti-keyrelease/pkg/apis/cti/v1"
	"k8s.io/api/admission/v1beta1"
)

// Uncomment out the code below to display messages from "glog"

func init() {
	flag.Set("alsologtostderr", fmt.Sprintf("%t", true))
	var logLevel string
	flag.StringVar(&logLevel, "logLevel", "5", "test")
	flag.Lookup("v").Value.Set(logLevel)
}

type cigKubeTest struct {
	ret ctiv1.ClusterTI
}

func NewCigKubeTest(ret ctiv1.ClusterTI) *cigKubeTest {
	return &cigKubeTest{ret}
}

func (ck *cigKubeTest) GetClusterTI(namespace, name string) (ctiv1.ClusterTI, error) {
	return ck.ret, nil
}

func TestLoadInitFile(t *testing.T) {
	icc, err := loadInitContainerConfig("tests/ConfigFile.yaml")
	if err != nil {
		t.Errorf("Error loading InitContainerConfig %v", err)
		return
	}
	v := validateResults(getJSON(icc), "tests/ExpectInitContainerConfig.json")
	if v == 0 {
		t.Log("Results match expections")
	} else {
		t.Error("Results do not match expections")
	}
}

func TestPseudo_uuid(t *testing.T) {
	uuid, err := pseudo_uuid()
	if err != nil {
		t.Errorf("Error obtaining pseudo_uuid %v", err)
		return
	}
	t.Logf("UUID: %v", uuid)
}

func TestMutateInitialization(t *testing.T) {

	ret := ctiv1.ClusterTI{
		Info: ctiv1.ClusterTISpec{
			ClusterName:   "testCluster",
			ClusterRegion: "testRegion",
		},
	}
	clInfo := NewCigKubeTest(ret)

	icc, err := loadInitContainerConfig("tests/ConfigFile.yaml")
	if err != nil {
		t.Errorf("Error loading InitContainerConfig %v", err)
		return
	}

	whsvr := &WebhookServer{
		initcontainerConfig: icc,
		server:              &http.Server{},
		createVaultCert:     true,
		clusterInfo:         clInfo,
	}

	req := getFakeAdmissionRequest()
	pod := getFakePod()

	// get test result of running mutateInitialization method:
	result, err := whsvr.mutateInitialization(pod, &req)
	if err != nil {
		t.Errorf("Error executing mutateInitialization %v", err)
		return
	}

	// one of the Annotation fields is dynamically set (UUID), so it needs to be
	// changed to static, for comparison
	annot := result.Annotations
	annot["admission.trusted.identity/ti-secret-key"] = "ti-secret-XXX"
	result.Annotations = annot

	// convert the result JSON to []byte
	resultB, err := json.Marshal(result)
	if err != nil {
		t.Errorf("Error marshal Result to []byte: %v", err)
		return
	}

	// get the exepected result from a file
	dat, err := ioutil.ReadFile("tests/ExpectMutateInit.json")
	if err != nil {
		t.Errorf("%v", err)
		return
	}
	expect := InitContainerConfig{}
	json.Unmarshal(dat, &expect)

	// convert the expect JSON to []byte
	expectB, err := json.Marshal(expect)
	if err != nil {
		t.Errorf("Error marshal Expected to []byte: %v", err)
		return
	}

	// Execute JSON diff on both byte representations of JSON
	// when using DefaultHTMLOptions, `text` can be treated as
	// HTML with <pre> to show differences with colors
	opts := jsondiff.DefaultHTMLOptions()
	diff, text := jsondiff.Compare(expectB, resultB, &opts)

	if diff == jsondiff.FullMatch {
		t.Logf("Results match expections: %v", diff)
	} else {
		t.Errorf("Results do not match expections: %v %v", diff, text)
		return
	}
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

func getInitContainerConfig() InitContainerConfig {
	s := getContentOfTheFile("tests/FakeInitContainerConfig.json")
	obj := InitContainerConfig{}
	json.Unmarshal([]byte(s), &obj)
	return obj
}

func validateResults(result string, expectedFile string) int {
	s := getContentOfTheFile(expectedFile)
	return strings.Compare(result, s)
}
