/*
Copyright 2017 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// +genclient
// +genclient:noStatus
// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

// Example is a specification for an Example resource
type ClusterTI struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata"`

	Spec   ClusterTISpec   `json:"spec"`
	Status ClusterTIStatus `json:"status,omitempty"`
}

// ExampleSpec is the spec for an Example resource
type ClusterTISpec struct {
	Foo string `json:"foo"`
	Bar bool   `json:"bar"`
}

// ExampleStatus is the status for an Example resource
type ClusterTIStatus struct {
	State   ClusterTIState `json:"state,omitempty"`
	Message string       `json:"message,omitempty"`
}

type ClusterTIState string

const (
	ExampleStateCreated   ClusterTIState = "Created"
	ExampleStateProcessed ClusterTIState = "Processed"
)

// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

// ExampleList is a list of Example resources
type ClusterTIList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata"`

	Items []ClusterTI `json:"items"`
}
