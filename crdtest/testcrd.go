package main

import (
	"fmt"
	ctiv1 "github.ibm.com/brandon-lum/ti-keyrelease/pkg/client/clientset/versioned/typed/cti/v1"
	meta_v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/rest"
)

func main() {
	config, err := rest.InClusterConfig()
	if err != nil {
		fmt.Printf("Err: %v", err)
		return
	}

	client, err := ctiv1.NewForConfig(config)
	if err != nil {
		fmt.Printf("Err: %v", err)
		return
	}

	cti, err := client.ClusterTIs("default").Get("test", meta_v1.GetOptions{})
	if err != nil {
		fmt.Printf("Err: %v", err)
		return
	}

	_ = cti
	return
}
