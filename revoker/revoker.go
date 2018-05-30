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

package main

import (
	"flag"
	"fmt"
	"time"
    "strings" 

	"github.com/golang/glog"

	"k8s.io/api/core/v1"
	meta_v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/util/workqueue"

    ccorev1 "k8s.io/client-go/kubernetes/typed/core/v1"
    "k8s.io/client-go/rest"
)

var (
    RConfig = RevokerConfig{}
)

// RevokerConfig contains the configuration of the revoker
type RevokerConfig struct {
    // Namespace is the namespace to monitor for revocations
    Namespace string
}

type Controller struct {
	indexer  cache.Indexer
	queue    workqueue.RateLimitingInterface
	informer cache.Controller
	cv1Client *ccorev1.CoreV1Client
}

func NewController(queue workqueue.RateLimitingInterface, indexer cache.Indexer, informer cache.Controller, cv1Client *ccorev1.CoreV1Client) *Controller {
	return &Controller{
		informer: informer,
		indexer:  indexer,
		queue:    queue,
        cv1Client: cv1Client,
	}
}

func (c *Controller) processNextItem() bool {
	// Wait until there is a new item in the working queue
	key, quit := c.queue.Get()
	if quit {
		return false
	}
	// Tell the queue that we are done with processing this key. This unblocks the key for other workers
	// This allows safe parallel processing because two pods with the same key are never processed in
	// parallel.
	defer c.queue.Done(key)

	// Invoke the method containing the business logic
	err := c.syncToStdout(key.(string))
	// Handle the error if something went wrong during the execution of the business logic
	c.handleErr(err, key)
	return true
}

// syncToStdout is the business logic of the controller. In this controller it simply prints
// information about the pod to stdout. In case an error happened, it has to simply return the error.
// The retry logic should not be part of the business logic.
func (c *Controller) syncToStdout(key string) error {
	_, exists, err := c.indexer.GetByKey(key)
	if err != nil {
		glog.Errorf("Fetching object with key %s from store failed with %v", key, err)
		return err
	}

	if !exists {
		// Below we will warm up our cache with a Pod, so that we will see a delete for one pod
		fmt.Printf("Pod %s does not exist anymore, revoking certs \n", key)
        podName := strings.TrimPrefix(key, RConfig.Namespace + "/")
        labelSelector := &meta_v1.LabelSelector{
            MatchLabels: map[string]string { "ti-pod-name" : podName },
        }
        secretList, err := c.cv1Client.Secrets(RConfig.Namespace).List(meta_v1.ListOptions{LabelSelector: meta_v1.FormatLabelSelector(labelSelector)})
        if err != nil {
            glog.Errorf("Error getting secret list for pod %v: %v", key, err)
            return err
        }

        for _, secret := range secretList.Items {
            fmt.Printf("Revoking and deleting cert from secret: %v\n", secret.ObjectMeta.Name)
            if err = c.cv1Client.Secrets(RConfig.Namespace).Delete (secret.ObjectMeta.Name, &meta_v1.DeleteOptions{}); err != nil {
                glog.Errorf("Failed to delete secret")
                return err
            }
        }
	} else {
		// Note that you also have to check the uid if you have a local controlled resource, which
		// is dependent on the actual instance, to detect that a Pod was recreated with the same name
		//fmt.Printf("Sync/Add/Update for Pod %s\n", obj.(*v1.Pod).GetName())
	}
	return nil
}

// handleErr checks if an error happened and makes sure we will retry later.
func (c *Controller) handleErr(err error, key interface{}) {
	if err == nil {
		// Forget about the #AddRateLimited history of the key on every successful synchronization.
		// This ensures that future processing of updates for this key is not delayed because of
		// an outdated error history.
		c.queue.Forget(key)
		return
	}

	// This controller retries 5 times if something goes wrong. After that, it stops trying.
	if c.queue.NumRequeues(key) < 5 {
		glog.Infof("Error syncing pod %v: %v", key, err)

		// Re-enqueue the key rate limited. Based on the rate limiter on the
		// queue and the re-enqueue history, the key will be processed later again.
		c.queue.AddRateLimited(key)
		return
	}

	c.queue.Forget(key)
	// Report to an external entity that, even after several retries, we could not successfully process this key
	runtime.HandleError(err)
	glog.Infof("Dropping pod %q out of the queue: %v", key, err)
}

func (c *Controller) Run(threadiness int, stopCh chan struct{}) {
	defer runtime.HandleCrash()

	// Let the workers stop when we are done
	defer c.queue.ShutDown()
	glog.Info("Starting Pod controller")

	go c.informer.Run(stopCh)

	// Wait for all involved caches to be synced, before processing items from the queue is started
	if !cache.WaitForCacheSync(stopCh, c.informer.HasSynced) {
		runtime.HandleError(fmt.Errorf("Timed out waiting for caches to sync"))
		return
	}

	for i := 0; i < threadiness; i++ {
		go wait.Until(c.runWorker, time.Second, stopCh)
	}

	<-stopCh
	glog.Info("Stopping Pod controller")
}

func (c *Controller) runWorker() {
	for c.processNextItem() {
	}
}

func main() {
    flag.StringVar(&RConfig.Namespace, "namespace", v1.NamespaceDefault, "Namespace to monitor for revokations")
	flag.Parse()
    //flag.Set("logtostderr", "true")

    // Get in-cluster config
    glog.Infof("Getting cluster Config")
    config, err := rest.InClusterConfig()
	if err != nil {
        glog.Infof("Cluster Config Err")
		glog.Fatal(err)
	}

	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
        glog.Infof("New Config Err")
		glog.Fatal(err)
	}

    // corev1 clientset
    cv1Client, err := ccorev1.NewForConfig(config)
    if err != nil {
        glog.Infof("New Config Err")
		glog.Fatal(err)
    }

/*

    // Create secret if it doesn't exist
    glog.Infof("Creating secret")
    createSecret, err = cv1Client.Secrets(namespace).Create(createSecret)
    if err != nil {
        if !errors.IsAlreadyExists(err) {
            glog.Infof("Err: %v", err)
            return nil, err
        }
    }
*/
_ = cv1Client

	// create the pod watcher
	podListWatcher := cache.NewListWatchFromClient(clientset.CoreV1().RESTClient(), "pods", RConfig.Namespace, fields.Everything())

	// create the workqueue
	queue := workqueue.NewRateLimitingQueue(workqueue.DefaultControllerRateLimiter())

	// Bind the workqueue to a cache with the help of an informer. This way we make sure that
	// whenever the cache is updated, the pod key is added to the workqueue.
	// Note that when we finally process the item from the workqueue, we might see a newer version
	// of the Pod than the version which was responsible for triggering the update.
	indexer, informer := cache.NewIndexerInformer(podListWatcher, &v1.Pod{}, 0, cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj interface{}) {
			//key, err := cache.MetaNamespaceKeyFunc(obj)
			//if err == nil {
			//	queue.Add(key)
			//}
		},
		UpdateFunc: func(old interface{}, new interface{}) {
			//key, err := cache.MetaNamespaceKeyFunc(new)
			//if err == nil {
			//	queue.Add(key)
			//}
		},
		DeleteFunc: func(obj interface{}) {
			// IndexerInformer uses a delta queue, therefore for deletes we have to use this
			// key function.
			key, err := cache.DeletionHandlingMetaNamespaceKeyFunc(obj)
			if err == nil {
				queue.Add(key)
			}
		},
	}, cache.Indexers{})

	controller := NewController(queue, indexer, informer, cv1Client)

	// Now let's start the controller
	stop := make(chan struct{})
	defer close(stop)
	go controller.Run(1, stop)

	// Wait forever
	select {}
}
