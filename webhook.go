package main

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/ghodss/yaml"
	"github.com/golang/glog"
	"k8s.io/api/admission/v1beta1"
	admissionregistrationv1beta1 "k8s.io/api/admissionregistration/v1beta1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	v1 "k8s.io/kubernetes/pkg/apis/core/v1"

	"k8s.io/client-go/rest"

	ctiv1 "github.com/IBM/trusted-service-identity/pkg/apis/cti/v1"
	cctiv1 "github.com/IBM/trusted-service-identity/pkg/client/clientset/versioned/typed/cti/v1"
)

var (
	runtimeScheme = runtime.NewScheme()
	codecs        = serializer.NewCodecFactory(runtimeScheme)
	deserializer  = codecs.UniversalDeserializer()

	// (https://github.com/kubernetes/kubernetes/issues/57982)
	defaulter = runtime.ObjectDefaulter(runtimeScheme)
)

var tsiNamespace string

// when DEBUG=true, the local write to the file is enabled
var write bool = true

const (
	admissionWebhookAnnotationInjectKey     = "admission.trusted.identity/inject"
	admissionWebhookAnnotationStatusKey     = "admission.trusted.identity/status"
	admissionWebhookAnnotationImagesKey     = "admission.trusted.identity/tsi-images"
	admissionWebhookAnnotationClusterName   = "admission.trusted.identity/tsi-cluster-name"
	admissionWebhookAnnotationClusterRegion = "admission.trusted.identity/tsi-region"
)

// Webhook constants used for messaging
const (
	MsgNoCreate   string = "TSI Mutation Webhook disallowed this pod creation for safety reasons"
	MsgHostPath   string = "Using hostPath Volume with '/var/tsi-secure' is not allowed"
	MsgSidecarImg string = "Attempting to modify the sidecar image"
	MsgProtectNs  string = "Requesting TSI mutation in a protected namespace"
)

// Webhook errors types used for error matching
var (
	ErrHostpathSocket = errors.New(MsgHostPath)
	ErrSidecarImg     = errors.New(MsgSidecarImg)
	ErrProtectedNs    = errors.New(MsgProtectNs)
)

// WebhookServer struct
type WebhookServer struct {
	tsiMutateConfig *tsiMutateConfig
	server          *http.Server
	clusterInfo     ClusterInfoGetter
	// protectedNamespaces - list of namespaces that are protected and cannot execute the mutation
	protectedNamespaces []string
}

type ClusterInfoGetter interface {
	GetClusterTI(tsiNamespace string, policy string) (ctiv1.ClusterTI, error)
}

type cigKube struct {
	cticlient *cctiv1.TrustedV1Client
}

func NewCigKube() (*cigKube, error) {
	glog.Info("Getting cluster Config")
	kubeConf, err := rest.InClusterConfig()
	if err != nil {
		glog.Infof("Err: %v", err)
		return nil, err
	}
	cticlient, err := cctiv1.NewForConfig(kubeConf)
	if err != nil {
		fmt.Printf("Err: %v", err)
		return nil, err
	}
	ci := cigKube{
		cticlient: cticlient,
	}
	return &ci, nil
}

func (ck *cigKube) GetClusterTI(tsiNamespace string, policy string) (ctiv1.ClusterTI, error) {
	// get the client using KubeConfig
	glog.Infof("TSI Namespace : %v", tsiNamespace)
	cti, err := ck.cticlient.ClusterTIs(tsiNamespace).Get(policy, metav1.GetOptions{})
	if err != nil {
		fmt.Printf("Err: %v", err)
		return ctiv1.ClusterTI{}, err
	}
	return *cti, err
}

type tsiMutateConfig struct {
	InitContainers    []corev1.Container   `yaml:"initContainers"`
	SidecarContainers []corev1.Container   `yaml:"sidecarContainers"`
	Volumes           []corev1.Volume      `yaml:"volumes"`
	AddVolumeMounts   []corev1.VolumeMount `yaml:"addVolumeMounts"`
	Annotations       map[string]string    `yaml:"annotations"`
}

func (ic *tsiMutateConfig) DeepCopy() *tsiMutateConfig {
	icc := &tsiMutateConfig{
		InitContainers:    make([]corev1.Container, len(ic.InitContainers)),
		SidecarContainers: make([]corev1.Container, len(ic.SidecarContainers)),
		Volumes:           make([]corev1.Volume, len(ic.Volumes)),
		AddVolumeMounts:   make([]corev1.VolumeMount, len(ic.AddVolumeMounts)),
		Annotations:       make(map[string]string),
	}

	for i, v := range ic.InitContainers {
		icc.InitContainers[i] = *v.DeepCopy()
	}

	for i, v := range ic.SidecarContainers {
		icc.SidecarContainers[i] = *v.DeepCopy()
	}

	for i, v := range ic.Volumes {
		icc.Volumes[i] = *v.DeepCopy()
	}

	for i, v := range ic.AddVolumeMounts {
		icc.AddVolumeMounts[i] = *v.DeepCopy()
	}

	for k, v := range ic.Annotations {
		icc.Annotations[k] = v
	}

	return icc
}

type patchOperation struct {
	Op    string      `json:"op"`
	Path  string      `json:"path"`
	Value interface{} `json:"value,omitempty"`
}

func init() {
	_ = corev1.AddToScheme(runtimeScheme)
	_ = admissionregistrationv1beta1.AddToScheme(runtimeScheme)
	_ = ctiv1.AddToScheme(runtimeScheme)
	// defaulting with webhooks:
	// https://github.com/kubernetes/kubernetes/issues/57982
	_ = v1.AddToScheme(runtimeScheme)
}

// This function returns the array of protected namespaces. As a side effect, it
// sets the TSI Namespace `tsiNamespace`
func getProtectedNamespace(tsiNamespaceFile string) (protectedNamespaces []string, err error) {
	tsiNs, err := ioutil.ReadFile(tsiNamespaceFile)
	if err != nil {
		return nil, err
	}
	tsiNamespace = string(tsiNs)
	protectedNamespaces = []string{
		metav1.NamespaceSystem,
		metav1.NamespacePublic,
		tsiNamespace,
	}
	return protectedNamespaces, nil
}

// (https://github.com/kubernetes/kubernetes/issues/57982)
func applyDefaultsWorkaround(containers []corev1.Container, volumes []corev1.Volume) {
	defaulter.Default(&corev1.Pod{
		Spec: corev1.PodSpec{
			Containers: containers,
			Volumes:    volumes,
		},
	})
}

func loadtsiMutateConfig(configFile string) (*tsiMutateConfig, error) {
	data, err := ioutil.ReadFile(configFile)
	if err != nil {
		return nil, err
	}
	glog.Infof("New configuration: sha256sum %x", sha256.Sum256(data))

	var cfg tsiMutateConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}

	if cfg.Annotations == nil {
		cfg.Annotations = make(map[string]string)
	}
	// To generate a new `Expect` file for testing, uncomment out below:
	logJSON("ExpectTsiMutateConfig.json", cfg)
	return &cfg, nil
}

// isSafe validates the format of the request to check if the requested
// operation is permitted. For CREATE operations, it checks if the request
// contains references to protected socket and /etc Volumes.
// And since UPDATE operation does not allowed volume modifications, it only makes
// sure that sidecar image has not been modified
// it returns an error if operation is not permitted
func isSafe(pod *corev1.Pod, operationType string) error {

	// this output can be used for creating tests/FakeIsSafeXXX.json files
	glog.Infof("isSafe log. Operation %v", operationType)
	logJSON("FakeIsSafeX.json", pod)

	vols := pod.Spec.Volumes

	switch operationType {
	case "CREATE":
		for _, v := range vols {
			// glog.Infof("***** VNAME: %v VHOSTPATH: %v", v.Name, v.HostPath)
			if v.HostPath != nil && strings.Contains(v.HostPath.Path, "/var/tsi-secure") {
				return ErrHostpathSocket
			}
		}
	case "UPDATE":
		// volumes cannot be added nor modified on the update, but
		// we need to prevent image change for the sidecar
		conts := pod.Spec.Containers
		for _, c := range conts {
			// glog.Infof("****** CNAME: %v, CIMG: %v, CVOLUMEMOUNTS: %v", c.Name, c.Image, c.VolumeMounts)
			if c.Name == "jwt-sidecar" {
				// extract the image name, skip the version label
				// tsidentity/ti-jwt-sidecar:v1.3
				img := strings.Split(c.Image, ":")
				if img[0] == "tsidentity/ti-jwt-sidecar" {
					glog.Infof("Sidecar image matches! %v", c.Image)
				} else {
					return ErrSidecarImg
				}
			}
		}
	}
	return nil
}

// This function validates if the object is requested in protected namespace
func isProtectedNamespace(protectedList []string, metadata *metav1.ObjectMeta) bool {

	glog.Infof("isProtectedNamespace - protectedList: %v", protectedList)
	// this output can be used for creating tests/FakeMutationRequiredXXX.json files
	logJSON("FakeMutationRequired.json", metadata)

	// check if the special kubernetes system namespaces and protected TSI namespace used
	for _, protectedNamespace := range protectedList {
		if metadata.Namespace == protectedNamespace {
			glog.Infof("Pod %v in protected namespace: %v", metadata.GenerateName, metadata.Namespace)
			return true
		}
	}
	return false
}

// This function validates the entire logic to perform the mutation
// Steps:
//   1. If mutation request is done in the protected namespace, return error
//   2. Evaluate if the pod is safe to continue, return error otherwise
//   3. Return true if the pod can be mutated, false otherwise
func mutationRequired(protectedList []string, pod *corev1.Pod, operation string) (bool, error) {

	metadata := pod.ObjectMeta
	annotations := metadata.GetAnnotations()
	if annotations == nil {
		annotations = map[string]string{}
	}
	var isMutate bool
	switch strings.ToLower(annotations[admissionWebhookAnnotationInjectKey]) {
	case "y", "yes", "true", "on":
		isMutate = true
	default:
		isMutate = false
	}
	logJSON("FakePod.json", &pod)

	if isProtectedNamespace(protectedList, &metadata) {

		// mutation is not allowed in the protected namespace
		if isMutate {
			glog.Errorf("Mutation requested in the protected namespace")
			return isMutate, ErrProtectedNs
		}

		glog.Infof("No mutation requested for %v in %v namespace", pod.GenerateName, pod.Namespace)
		return false, nil
	}

	// if the namespace is not protected

	// check if the request is safe
	err := isSafe(pod, operation)
	if err != nil {
		glog.Error(err.Error())
		return isMutate, err
	}
	glog.Infof("It is safe to continue with %v for pod %v in %v. Mutate=%v",
		operation, pod.GenerateName, pod.Namespace, isMutate)
	return isMutate, nil
}

func addContainer(target, added []corev1.Container, basePath string) (patch []patchOperation) {
	// this output can be used for creating tests/FakeAddContainer.json files
	logJSON("FakeAddContainerTarget.json", target)
	logJSON("FakeAddContainer.json", added)

	first := len(target) == 0
	var value interface{}
	for _, add := range added {
		value = add
		path := basePath
		if first {
			first = false
			value = []corev1.Container{add}
		} else {
			path = path + "/-"
		}
		patch = append(patch, patchOperation{
			Op:    "add",
			Path:  path,
			Value: value,
		})
	}

	// this output can be used for creating tests/ExpectedAddContainer.json file
	logJSON("ExpectAddContainer.json", patch)
	return patch
}

func prependContainer(target, added []corev1.Container, basePath string) (patch []patchOperation) {
	// this output can be used for creating tests/FakePrependContainer.json files
	logJSON("FakePrependContainerTarget.json", target)
	logJSON("FakePrependContainer.json", added)

	first := len(target) == 0
	var value interface{}
	for _, add := range added {
		value = add
		path := basePath
		if first {
			first = false
			value = []corev1.Container{add}
		} else {
			path = path + "/0"
		}
		patch = append(patch, patchOperation{
			Op:    "add",
			Path:  path,
			Value: value,
		})
	}

	// this output can be used for creating tests/ExpectedPrependContainer.json file
	logJSON("ExpectPrependContainer.json", patch)
	return patch
}

func addVolume(target, added []corev1.Volume, basePath string) (patch []patchOperation) {

	// this output can be used for creating tests/FakeAddVolume.json files
	logJSON("FakeAddVolumeTarget.json", target)
	logJSON("FakeAddVolume.json", added)

	first := len(target) == 0
	var value interface{}
	for _, add := range added {
		value = add
		path := basePath
		if first {
			first = false
			value = []corev1.Volume{add}
		} else {
			path = path + "/-"
		}
		patch = append(patch, patchOperation{
			Op:    "add",
			Path:  path,
			Value: value,
		})
	}
	// this output can be used for creating tests/ExpectedVolumeM.json file
	logJSON("ExpectAddVolume.json", patch)
	return patch
}

func addVolumeMount(target, added []corev1.VolumeMount, basePath string) (patch []patchOperation) {
	// this output can be used for creating tests/FakeVolumeMount.json files
	logJSON("FakeAddVolumeMountTarget.json", target)
	logJSON("FakeAddVolumeMount.json", added)

	first := len(target) == 0
	var value interface{}
	for _, add := range added {
		value = add
		path := basePath
		if first {
			first = false
			value = []corev1.VolumeMount{add}
		} else {
			path = path + "/-"
		}
		patch = append(patch, patchOperation{
			Op:    "add",
			Path:  path,
			Value: value,
		})
	}
	// this output can be used for creating tests/ExpectedVolumeMount.json file
	logJSON("ExpectAddVolumeMount.json", patch)
	return patch
}

func updateAnnotation(target map[string]string, added map[string]string) (patch []patchOperation) {

	// this output can be used for creating tests/FakeUpdateAnnotation.json files
	logJSON("FakeUpdateAnnotationTarget.json", target)
	logJSON("FakeUpdateAnnotation.json", added)

	// cannot add individual path values. Must add the entire Annotation object
	// so add/replace new values then patch it all at once
	if target == nil {
		target = map[string]string{}
	}
	for key, value := range added {
		target[key] = value
	}

	patch = append(patch, patchOperation{
		Op:    "replace",
		Path:  "/metadata/annotations",
		Value: target,
	})

	// this output can be used for creating tests/ExpectedUpdateAnnotation.json files
	logJSON("ExpectUpdateAnnotation.json", patch)
	return patch
}

// If return nil, no changes required
func (whsvr *WebhookServer) mutateInitialization(pod corev1.Pod, req *v1beta1.AdmissionRequest) (*tsiMutateConfig, error) {

	// To generate a content for a new `Fake` file for testing, uncomment out below:
	logJSON("FakeAdmissionRequest.json", req)
	//logJSON("FakePod.json", &pod)

	tsiMutateConfigCp := whsvr.tsiMutateConfig.DeepCopy()

	glog.Infof("Applying defaults")

	// Workaround: https://github.com/kubernetes/kubernetes/issues/57982
	applyDefaultsWorkaround(tsiMutateConfigCp.InitContainers, tsiMutateConfigCp.Volumes)

	var err error

	/*
		    // XXX: Added workaround for //github.com/kubernetes/kubernetes/issues/57982
		    // for service accounts
		    if len(pod.Spec.Containers) == 0 {
		        err =  fmt.Errorf("Pod has no containers")
				glog.Infof("Err: %v", err)
		        return nil, err
		    }

		    var serviceaccountVolMount corev1.VolumeMount
		    foundServiceAccount := false
		    for _, vmount := range pod.Spec.Containers[0].VolumeMounts {
		        if strings.Contains(vmount.Name , "token") {
		            serviceaccountVolMount = vmount
		            foundServiceAccount = true
		            break
		        }
		    }

		    if !foundServiceAccount {
		        err =  fmt.Errorf("service account token not found")
				glog.Infof("Err: %v", err)
		        return nil, err
		    }

		    for i, c := range tsiMutateConfigCp.InitContainers {
		        glog.Infof("add vol mounts (initc) : %v", c.VolumeMounts, serviceaccountVolMount)
		        tsiMutateConfigCp.InitContainers[i].VolumeMounts = append(c.VolumeMounts, serviceaccountVolMount)
		    }
	*/
	cti, err := whsvr.clusterInfo.GetClusterTI(tsiNamespace, "cluster-policy")
	if err != nil {
		fmt.Printf("Err: %v", err)
		return nil, err
	}

	glog.Infof("Got CTI: %#v", cti)
	glog.Infof("CTI Cluster Name: %v", cti.Info.ClusterName)
	glog.Infof("CTI Cluster Region: %v", cti.Info.ClusterRegion)

	// Get list of images
	images := ""
	// Containers images should go first (since they are alphabetically before initContainers)
	for _, cspec := range pod.Spec.Containers {
		if images == "" {
			images = cspec.Image
		} else {
			images = images + "," + cspec.Image
		}
	}

	for _, cspec := range pod.Spec.InitContainers {
		if images == "" {
			images = cspec.Image
		} else {
			images = images + "," + cspec.Image
		}
	}

	tsiMutateConfigCp.Annotations[admissionWebhookAnnotationStatusKey] = "mutated"
	tsiMutateConfigCp.Annotations[admissionWebhookAnnotationImagesKey] = images
	tsiMutateConfigCp.Annotations[admissionWebhookAnnotationClusterName] = cti.Info.ClusterName
	tsiMutateConfigCp.Annotations[admissionWebhookAnnotationClusterRegion] = cti.Info.ClusterRegion

	// To generate a content for a new `Expect` file for testing, uncomment out below:
	logJSON("ExpectMutateInit.json", tsiMutateConfigCp)
	return tsiMutateConfigCp, nil
}

// create mutation patch for resoures
func createPatch(pod *corev1.Pod, tsiMutateConfig *tsiMutateConfig) ([]byte, error) {
	var patch []patchOperation

	// by default, mutate the pod with the new sidecar and required volumes
	var mutateAll bool = true

	// check if the pod already mutated, if so, only update the annotations
	currentAnnotations := pod.ObjectMeta.GetAnnotations()
	if currentAnnotations != nil {
		status := currentAnnotations[admissionWebhookAnnotationStatusKey]
		if strings.ToLower(status) == "mutated" {
			glog.Infof("Pod already mutated. Update only the annotations")
			mutateAll = false
		}
	}

	// always get updated annotations
	annotations := tsiMutateConfig.Annotations
	patch = append(patch, updateAnnotation(pod.Annotations, annotations)...)
	glog.Infof("Annotations are always updated. New values: %#v", annotations)

	// update everything only if not mutated before
	if mutateAll {
		// Add initContainer to populate secret before other initContainers so they have access to secrets as well
		for i, c := range pod.Spec.InitContainers {
			patch = append(patch, addVolumeMount(c.VolumeMounts, tsiMutateConfig.AddVolumeMounts, fmt.Sprintf("/spec/initContainers/%d/volumeMounts", i))...)
		}
		patch = append(patch, prependContainer(pod.Spec.InitContainers, tsiMutateConfig.InitContainers,
			"/spec/initContainers")...)

		patch = append(patch, addContainer(pod.Spec.Containers, tsiMutateConfig.SidecarContainers,
			"/spec/containers")...)
		patch = append(patch, addVolume(pod.Spec.Volumes, tsiMutateConfig.Volumes, "/spec/volumes")...)

		for i, c := range pod.Spec.Containers {
			patch = append(patch, addVolumeMount(c.VolumeMounts, tsiMutateConfig.AddVolumeMounts, fmt.Sprintf("/spec/containers/%d/volumeMounts", i))...)
		}
	}

	return json.Marshal(patch)
}

// main mutation process
func (whsvr *WebhookServer) mutate(ar *v1beta1.AdmissionReview) *v1beta1.AdmissionResponse {
	// To generate a content for a new `Fake` file for testing, uncomment out below:
	logJSON("FakeAdmissionReview.json", ar)

	req := ar.Request

	var pod corev1.Pod
	if err := json.Unmarshal(req.Object.Raw, &pod); err != nil {
		glog.Errorf("Could not unmarshal raw object: %v", err)
		return &v1beta1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	glog.Infof("AdmissionReview for Namespace=%v PodName=%v UID=%v patchOperation=%v UserInfo=%v",
		req.Namespace, pod.GenerateName, req.UID, req.Operation, req.UserInfo)

	// assign the request namespace to the pod
	podNamespace := req.Namespace
	if podNamespace == metav1.NamespaceNone {
		podNamespace = metav1.NamespaceDefault
	}
	pod.Namespace = podNamespace
	pod.ObjectMeta.Namespace = podNamespace

	// log.Infof("Safe to continue with %v/%v", pod.GenerateName, pod.Namespace)
	isMutate, err := mutationRequired(whsvr.protectedNamespaces, &pod, string(req.Operation))
	if err != nil {
		glog.Infof("Not safe to continue with %v for pod: %v/%v. Disallowing", req.Operation, pod.GenerateName, pod.Namespace)
		reason := metav1.StatusReason(MsgNoCreate)
		return &v1beta1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: err.Error(),
				Reason:  reason,
			},
		}
	}

	if !isMutate {
		glog.Infof("No mutation requested for %v in %v namespace", pod.GenerateName, pod.Namespace)
		return &v1beta1.AdmissionResponse{
			Allowed: true,
		}
	}

	glog.Infof("Mutation requested for %v in %v namespace", pod.GenerateName, pod.Namespace)

	// Mutation Initialization
	tsiMutateConfig, err := whsvr.mutateInitialization(pod, req)

	if err != nil {
		glog.Infof("Err: %v", err)
		return &v1beta1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}
	if tsiMutateConfig == nil {
		return &v1beta1.AdmissionResponse{
			Allowed: true,
		}
	}

	// Create TI secret key to populate
	glog.Infof("Creating patch")
	patchBytes, err := createPatch(&pod, tsiMutateConfig)
	if err != nil {
		return &v1beta1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	// glog.Infof("AdmissionResponse: patch=%v\n", string(patchBytes))
	return &v1beta1.AdmissionResponse{
		Allowed: true,
		Patch:   patchBytes,
		PatchType: func() *v1beta1.PatchType {
			pt := v1beta1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}

// Serve method for webhook server
func (whsvr *WebhookServer) serve(w http.ResponseWriter, r *http.Request) {
	var body []byte
	if r.Body != nil {
		if data, err := ioutil.ReadAll(r.Body); err == nil {
			body = data
		}
	}
	if len(body) == 0 {
		glog.Error("empty body")
		http.Error(w, "empty body", http.StatusBadRequest)
		return
	}

	// verify the content type is accurate
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/json" {
		glog.Errorf("Content-Type=%s, expect application/json", contentType)
		http.Error(w, "invalid Content-Type, expect `application/json`", http.StatusUnsupportedMediaType)
		return
	}

	var admissionResponse *v1beta1.AdmissionResponse
	ar := v1beta1.AdmissionReview{}
	if _, _, err := deserializer.Decode(body, nil, &ar); err != nil {
		glog.Errorf("Can't decode body: %v", err)
		admissionResponse = &v1beta1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	} else {
		admissionResponse = whsvr.mutate(&ar)
	}

	admissionReview := v1beta1.AdmissionReview{}
	if admissionResponse != nil {
		admissionReview.Response = admissionResponse
		if ar.Request != nil {
			admissionReview.Response.UID = ar.Request.UID
		}
	}

	resp, err := json.Marshal(admissionReview)
	if err != nil {
		glog.Errorf("Can't encode the response: %v", err)
		http.Error(w, fmt.Sprintf("could not encode the response: %v", err), http.StatusInternalServerError)
	}
	glog.Infof("Ready to write the reponse ...")
	if _, err := w.Write(resp); err != nil {
		glog.Errorf("Can't write response: %v", err)
		http.Error(w, fmt.Sprintf("could not write the response: %v", err), http.StatusInternalServerError)
	}
}

// Log the JSON format of the object
func logJSON(msg string, v interface{}) {

	if os.Getenv("DEBUG") == "true" {
		s := getJSON(v)
		glog.Infof("JSON for %v:\n %v", msg, s)

		if write {
			f, err := os.Create(filepath.Join(os.TempDir(), msg))
			if err != nil {
				panic(err)
			}
			defer f.Close()

			_, err = f.WriteString(s)
			if err != nil {
				panic(err)
			}
			glog.Infof("Logged successfully to %s", f.Name())
		}
	}
}

func getJSON(v interface{}) string {
	// Dump the object so it can be used for testing
	b, er := json.MarshalIndent(v, "", "    ")
	if er != nil {
		panic(er)
	}
	b2 := append(b, '\n')
	return string(b2)
}
