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

// Webhook Server parameters
type WhSvrParameters struct {
	port                    int    // webhook server port
	createVaultCert         bool   // true to inject keys on init
	certFile                string // path to the x509 certificate for https
	keyFile                 string // path to the x509 private key matching `CertFile`
	initcontainerCfgFile    string // path to initContainer injector configuration file
	sidecarcontainerCfgFile string // path to sidecarContainer configuration file
}

func main() {
	var parameters WhSvrParameters

	// get command line parameters
	flag.IntVar(&parameters.port, "port", 443, "Webhook server port.")
	flag.BoolVar(&parameters.createVaultCert, "createVaultCert", true, "Boolean to insert keys to Vault on init")
	flag.StringVar(&parameters.certFile, "tlsCertFile", "/etc/webhook/certs/cert.pem", "File containing the x509 Certificate for HTTPS.")
	flag.StringVar(&parameters.keyFile, "tlsKeyFile", "/etc/webhook/certs/key.pem", "File containing the x509 private key to --tlsCertFile.")
	flag.StringVar(&parameters.initcontainerCfgFile, "initcontainerCfgFile", "/etc/webhook/config/initcontainerconfig.yaml", "File containing the mutation configuration.")
	flag.Parse()

	initcontainerConfig, err := loadInitContainerConfig(parameters.initcontainerCfgFile)
	if err != nil {
		glog.Errorf("Filed to load configuration: %v", err)
	}

	pair, err := tls.LoadX509KeyPair(parameters.certFile, parameters.keyFile)
	if err != nil {
		glog.Errorf("Filed to load key pair: %v", err)
	}

	whsvr := &WebhookServer{
		initcontainerConfig: initcontainerConfig,
		server: &http.Server{
			Addr:      fmt.Sprintf(":%v", parameters.port),
			TLSConfig: &tls.Config{Certificates: []tls.Certificate{pair}},
		},
		createVaultCert: parameters.createVaultCert,
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
