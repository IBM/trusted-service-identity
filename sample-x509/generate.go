package main

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"time"
)

func panice(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	// The "never expires" timestamp from RFC5280
	neverExpires := time.Date(9999, 12, 31, 23, 59, 59, 0, time.UTC)

	rootKey := generateRSAKey()
	writeKey("root.key.pem", rootKey)

	rootCert := createRootCertificate(rootKey, &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		BasicConstraintsValid: true,
		IsCA:                  true,
		NotAfter:              neverExpires,
	})

	intermediateKey := generateRSAKey()
	writeKey("intermediate.key.pem", intermediateKey)

	intermediateCert := createCertificate(intermediateKey, &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		BasicConstraintsValid: true,
		IsCA:                  true,
		NotAfter:              neverExpires,
	}, rootKey, rootCert)

	nodeKey := generateRSAKey()

	nodeCert := createCertificate(nodeKey, &x509.Certificate{
		SerialNumber: big.NewInt(1),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		NotAfter:     neverExpires,
		Subject:      pkix.Name{CommonName: "some common name1"},
	}, intermediateKey, intermediateCert)

	writeKey("node1.key.pem", nodeKey)
	writeCerts("node1-bundle.cert.pem", nodeCert, intermediateCert)
	writeCerts("node1.cert.pem", nodeCert)
	writeCerts("intermediate.cert.pem", intermediateCert)
	writeCerts("root.cert.pem", rootCert)

	nodeKey = generateRSAKey()

	nodeCert = createCertificate(nodeKey, &x509.Certificate{
		SerialNumber: big.NewInt(1),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		NotAfter:     neverExpires,
		Subject:      pkix.Name{CommonName: "some common name2"},
	}, intermediateKey, intermediateCert)

	writeKey("node2.key.pem", nodeKey)
	writeCerts("node2-bundle.cert.pem", nodeCert, intermediateCert)
	writeCerts("node2.cert.pem", nodeCert)

	nodeKey = generateRSAKey()

	nodeCert = createCertificate(nodeKey, &x509.Certificate{
		SerialNumber: big.NewInt(1),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		NotAfter:     neverExpires,
		Subject:      pkix.Name{CommonName: "some common name3"},
	}, intermediateKey, intermediateCert)

	writeKey("node3.key.pem", nodeKey)
	writeCerts("node3-bundle.cert.pem", nodeCert, intermediateCert)
	writeCerts("node3.cert.pem", nodeCert)
}

func createRootCertificate(key *rsa.PrivateKey, tmpl *x509.Certificate) *x509.Certificate {
	return createCertificate(key, tmpl, key, tmpl)
}

func createCertificate(key *rsa.PrivateKey, tmpl *x509.Certificate, parentKey *rsa.PrivateKey, parent *x509.Certificate) *x509.Certificate {
	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, parent, &key.PublicKey, parentKey)
	panice(err)
	cert, err := x509.ParseCertificate(certDER)
	panice(err)
	return cert
}

func generateRSAKey() *rsa.PrivateKey {
	key, err := rsa.GenerateKey(rand.Reader, 768) //nolint: gosec // small key is to keep test fast... not a security feature
	panice(err)
	return key
}

func writeKey(path string, key interface{}) {
	keyBytes, err := x509.MarshalPKCS8PrivateKey(key)
	panice(err)
	pemBytes := pem.EncodeToMemory(&pem.Block{
		Type:  "PRIVATE KEY",
		Bytes: keyBytes,
	})
	err = os.WriteFile(path, pemBytes, 0600)
	panice(err)
}

func writeCerts(path string, certs ...*x509.Certificate) {
	data := new(bytes.Buffer)
	for _, cert := range certs {
		err := pem.Encode(data, &pem.Block{
			Type:  "CERTIFICATE",
			Bytes: cert.Raw,
		})
		panice(err)
	}
	err := os.WriteFile(path, data.Bytes(), 0600)
	panice(err)
}
