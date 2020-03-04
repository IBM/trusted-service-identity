package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/golang/glog"
)

// WhSvrParameters - Webhook Server parameters
type WhSvrParameters struct {
	port                    int    // webhook server port
	certFile                string // path to the x509 certificate for https
	keyFile                 string // path to the x509 private key matching `CertFile`
	tsiMutateConfigFile     string // path to tsiMutate configuration file
	sidecarcontainerCfgFile string // path to sidecarContainer configuration file
}

func main() {
	var parameters WhSvrParameters

	// get command line parameters
	flag.IntVar(&parameters.port, "port", 443, "Webhook server port.")
	flag.StringVar(&parameters.certFile, "tlsCertFile", "/etc/webhook/certs/cert.pem", "File containing the x509 Certificate for HTTPS.")
	flag.StringVar(&parameters.keyFile, "tlsKeyFile", "/etc/webhook/certs/key.pem", "File containing the x509 private key to --tlsCertFile.")
	flag.StringVar(&parameters.tsiMutateConfigFile, "tsiMutateConfigFile", "/etc/webhook/config/tsiMutateConfig.yaml", "File containing the mutation configuration.")
	flag.Parse()

	tsiMutateConfig, err := loadtsiMutateConfig(parameters.tsiMutateConfigFile)
	if err != nil {
		glog.Errorf("Failed to load configuration: %v", err)
	}
	logJSON("tsiMutateConfig(main)", tsiMutateConfig)

	pair, err := tls.LoadX509KeyPair(parameters.certFile, parameters.keyFile)
	if err != nil {
		glog.Errorf("Failed to load key pair: %v", err)
	}

	clInfo, err := NewCigKube()
	if err != nil {
		glog.Errorf("Failed to create ClusterInfo: %v", err)
	}

	whsvr := &WebhookServer{
		tsiMutateConfig: tsiMutateConfig,
		server: &http.Server{
			Addr:      fmt.Sprintf(":%v", parameters.port),
			TLSConfig: &tls.Config{Certificates: []tls.Certificate{pair}},
		},
		clusterInfo: clInfo,
	}

	// define http server and server handler
	mux := http.NewServeMux()
	mux.HandleFunc("/mutate", whsvr.serve)
	whsvr.server.Handler = mux

	// start webhook server in new rountine
	go func() {
		if err := whsvr.server.ListenAndServeTLS("", ""); err != nil {
			glog.Errorf("Filed to listen and serve webhook server: %v", err)
		}
	}()

	// listening OS shutdown singal
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, syscall.SIGINT, syscall.SIGTERM)
	<-signalChan

	glog.Infof("Got OS shutdown signal, shutting down wenhook server gracefully...")
	whsvr.server.Shutdown(context.Background())
}
