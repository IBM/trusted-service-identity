package jwtauth

import (
	"context"
	//"crypto/ecdsa"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/hashicorp/vault/logical"
	"github.com/pkg/errors"
	jose "gopkg.in/square/go-jose.v2"
	"gopkg.in/square/go-jose.v2/jwt"
)

func setupBackend(t *testing.T, oidc, audience bool) (logical.Backend, logical.Storage) {
	b, storage := getBackend(t)

	var data map[string]interface{}
	if oidc {
		data = map[string]interface{}{
			"bound_issuer":       "https://team-vault.auth0.com/",
			"oidc_discovery_url": "https://team-vault.auth0.com/",
		}
	} else {
		data = map[string]interface{}{
			"bound_issuer":           "https://team-vault.auth0.com/",
			"jwt_validation_pubkeys": pubCA,
		}
	}

	req := &logical.Request{
		Operation: logical.UpdateOperation,
		Path:      configPath,
		Storage:   storage,
		Data:      data,
	}

	resp, err := b.HandleRequest(context.Background(), req)
	if err != nil || (resp != nil && resp.IsError()) {
		t.Fatalf("err:%s resp:%#v\n", err, resp)
	}

	data = map[string]interface{}{
		"bound_subject": "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
		"user_claim":    "https://vault/user",
		"groups_claim":  "https://vault/groups",
		"policies":      "test",
		"period":        "3s",
		"ttl":           "1s",
		"num_uses":      12,
		"max_ttl":       "5s",
	}
	if audience {
		data["bound_audiences"] = "https://vault.plugin.auth.jwt.test"
	}

	req = &logical.Request{
		Operation: logical.CreateOperation,
		Path:      "role/plugin-test",
		Storage:   storage,
		Data:      data,
	}

	resp, err = b.HandleRequest(context.Background(), req)
	if err != nil || (resp != nil && resp.IsError()) {
		t.Fatalf("err:%s resp:%#v\n", err, resp)
	}

	return b, storage
}

func getTestJWT(t *testing.T, privKey string, cl jwt.Claims, privateCl interface{}) (string, *rsa.PrivateKey) {
	t.Helper()
	var key *rsa.PrivateKey
	block, _ := pem.Decode([]byte(privKey))
	if block != nil {
		var err error
		key, err = x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			t.Fatal(err)
		}
	}

	sig, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: key}, (&jose.SignerOptions{}).WithType("JWT"))
	if err != nil {
		t.Fatal(err)
	}

	raw, err := jwt.Signed(sig).Claims(cl).Claims(privateCl).CompactSerialize()
	if err != nil {
		t.Fatal(err)
	}

	return raw, key
}

func getTestOIDC(t *testing.T) string {
	if os.Getenv("OIDC_CLIENT_SECRET") == "" {
		t.SkipNow()
	}

	url := "https://team-vault.auth0.com/oauth/token"
	payload := strings.NewReader("{\"client_id\":\"r3qXcK2bix9eFECzsU3Sbmh0K16fatW6\",\"client_secret\":\"" + os.Getenv("OIDC_CLIENT_SECRET") + "\",\"audience\":\"https://vault.plugin.auth.jwt.test\",\"grant_type\":\"client_credentials\"}")
	req, err := http.NewRequest("POST", url, payload)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Add("content-type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}

	defer res.Body.Close()
	body, _ := ioutil.ReadAll(res.Body)

	type a0r struct {
		AccessToken string `json:"access_token"`
	}
	var out a0r
	err = json.Unmarshal(body, &out)
	if err != nil {
		t.Fatal(err)
	}

	//t.Log(out.AccessToken)
	return out.AccessToken
}

func TestLogin_JWT(t *testing.T) {
	// Test missing audience
	{
		b, storage := setupBackend(t, false, false)
		cl := jwt.Claims{
			Subject:   "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:    "https://team-vault.auth0.com/",
			NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Second)),
			Audience:  jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatal("expected error")
		}
		if !strings.Contains(resp.Error().Error(), "no audiences bound to the role") {
			t.Fatalf("unexpected error: %v", resp.Error())
		}
	}

	b, storage := setupBackend(t, false, true)

	// test valid inputs
	{
		cl := jwt.Claims{
			Subject:   "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:    "https://team-vault.auth0.com/",
			NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Second)),
			Audience:  jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if resp.IsError() {
			t.Fatalf("got error: %v", resp.Error())
		}

		auth := resp.Auth
		switch {
		case len(auth.Policies) != 1 || auth.Policies[0] != "test":
			t.Fatal(auth.Policies)
		case auth.Alias.Name != "jeff":
			t.Fatal(auth.Alias.Name)
		case len(auth.GroupAliases) != 2 || auth.GroupAliases[0].Name != "foo" || auth.GroupAliases[1].Name != "bar":
			t.Fatal(auth.GroupAliases)
		case auth.Period != 3*time.Second:
			t.Fatal(auth.Period)
		case auth.TTL != time.Second:
			t.Fatal(auth.TTL)
		case auth.MaxTTL != 5*time.Second:
			t.Fatal(auth.MaxTTL)
		}
	}

	// test bad signature
	{
		cl := jwt.Claims{
			Subject:   "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:    "https://team-vault.auth0.com/",
			NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Second)),
			Audience:  jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, badPrivKey, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatalf("expected error: %v", *resp)
		}
	}

	// test bad issuer
	{
		cl := jwt.Claims{
			Subject:   "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:    "https://team-fault.auth0.com/",
			NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Second)),
			Audience:  jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatalf("expected error: %v", *resp)
		}
	}

	// test bad audience
	{
		cl := jwt.Claims{
			Subject:   "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:    "https://team-vault.auth0.com/",
			NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Second)),
			Audience:  jwt.Audience{"https://fault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatalf("expected error: %v", *resp)
		}
	}

	// test bad subject
	{
		cl := jwt.Claims{
			Subject:   "p3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:    "https://team-vault.auth0.com/",
			NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Second)),
			Audience:  jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatalf("expected error: %v", *resp)
		}
	}

	// test bad expiry (using auto expiry)
	{
		cl := jwt.Claims{
			Subject:   "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:    "https://team-vault.auth0.com/",
			NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Hour)),
			Audience:  jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatalf("expected error: %v", *resp)
		}
	}

	// test bad notbefore (using auto)
	{
		cl := jwt.Claims{
			Subject:  "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:   "https://team-vault.auth0.com/",
			Expiry:   jwt.NewNumericDate(time.Now().Add(5 * time.Hour)),
			Audience: jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatalf("expected error: %v", *resp)
		}
	}

	// test auto notbefore from issue time
	{
		cl := jwt.Claims{
			Subject:  "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:   "https://team-vault.auth0.com/",
			Expiry:   jwt.NewNumericDate(time.Now().Add(5 * time.Second)),
			IssuedAt: jwt.NewNumericDate(time.Now().Add(-5 * time.Hour)),
			Audience: jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		privateCl := struct {
			User   string   `json:"https://vault/user"`
			Groups []string `json:"https://vault/groups"`
		}{
			"jeff",
			[]string{"foo", "bar"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if resp.IsError() {
			t.Fatalf("unexpected error: %v", resp.Error())
		}
	}

	// test missing user value
	{
		cl := jwt.Claims{
			Subject:  "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
			Issuer:   "https://team-vault.auth0.com/",
			Expiry:   jwt.NewNumericDate(time.Now().Add(5 * time.Second)),
			Audience: jwt.Audience{"https://vault.plugin.auth.jwt.test"},
		}

		jwtData, _ := getTestJWT(t, privCA, cl, struct{}{})

		data := map[string]interface{}{
			"role": "plugin-test",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil {
			t.Fatal("got nil response")
		}
		if !resp.IsError() {
			t.Fatalf("expected error: %v", *resp)
		}
	}
	// test bad role name
	{
		jwtData, _ := getTestJWT(t, privCA, jwt.Claims{}, struct{}{})

		data := map[string]interface{}{
			"role": "plugin-test-bad",
			"jwt":  jwtData,
		}

		req := &logical.Request{
			Operation: logical.UpdateOperation,
			Path:      "login",
			Storage:   storage,
			Data:      data,
		}

		resp, err := b.HandleRequest(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		if resp == nil || !resp.IsError() {
			t.Fatal("expected error")
		}
		if resp.Error().Error() != "role could not be found" {
			t.Fatalf("unexpected error: %s", resp.Error())
		}
	}
}

func TestLogin_OIDC(t *testing.T) {
	b, storage := setupBackend(t, true, true)

	jwtData := getTestOIDC(t)

	data := map[string]interface{}{
		"role": "plugin-test",
		"jwt":  jwtData,
	}

	req := &logical.Request{
		Operation: logical.UpdateOperation,
		Path:      "login",
		Storage:   storage,
		Data:      data,
	}

	resp, err := b.HandleRequest(context.Background(), req)
	if err != nil {
		t.Fatal(err)
	}
	if resp == nil {
		t.Fatal("got nil response")
	}
	if resp.IsError() {
		t.Fatalf("got error: %v", resp.Error())
	}

	auth := resp.Auth
	switch {
	case len(auth.Policies) != 1 || auth.Policies[0] != "test":
		t.Fatal(auth.Policies)
	case auth.Alias.Name != "jeff":
		t.Fatal(auth.Alias.Name)
	case len(auth.GroupAliases) != 2 || auth.GroupAliases[0].Name != "foo" || auth.GroupAliases[1].Name != "bar":
		t.Fatal(auth.GroupAliases)
	case auth.Period != 3*time.Second:
		t.Fatal(auth.Period)
	case auth.TTL != time.Second:
		t.Fatal(auth.TTL)
	case auth.MaxTTL != 5*time.Second:
		t.Fatal(auth.MaxTTL)
	}
}

func TestLogin_NestedGroups(t *testing.T) {
	b, storage := getBackend(t)

	data := map[string]interface{}{
		"bound_issuer":           "https://team-vault.auth0.com/",
		"jwt_validation_pubkeys": pubCA,
	}

	req := &logical.Request{
		Operation: logical.UpdateOperation,
		Path:      configPath,
		Storage:   storage,
		Data:      data,
	}

	resp, err := b.HandleRequest(context.Background(), req)
	if err != nil || (resp != nil && resp.IsError()) {
		t.Fatalf("err:%s resp:%#v\n", err, resp)
	}

	data = map[string]interface{}{
		"bound_audiences":                "https://vault.plugin.auth.jwt.test",
		"bound_subject":                  "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
		"user_claim":                     "https://vault/user",
		"groups_claim":                   "https://vault/groups.testing",
		"groups_claim_delimiter_pattern": ":.",
		"policies":                       "test",
		"period":                         "3s",
		"ttl":                            "1s",
		"num_uses":                       12,
		"max_ttl":                        "5s",
	}

	req = &logical.Request{
		Operation: logical.CreateOperation,
		Path:      "role/plugin-test",
		Storage:   storage,
		Data:      data,
	}

	resp, err = b.HandleRequest(context.Background(), req)
	if err != nil || (resp != nil && resp.IsError()) {
		t.Fatalf("err:%s resp:%#v\n", err, resp)
	}

	cl := jwt.Claims{
		Subject:   "r3qXcK2bix9eFECzsU3Sbmh0K16fatW6@clients",
		Issuer:    "https://team-vault.auth0.com/",
		NotBefore: jwt.NewNumericDate(time.Now().Add(-5 * time.Second)),
		Audience:  jwt.Audience{"https://vault.plugin.auth.jwt.test"},
	}

	type GroupsLevel2 struct {
		Groups []string `json:"testing"`
	}
	type GroupsLevel1 struct {
		Level2 GroupsLevel2 `json:"//vault/groups"`
	}
	privateCl := struct {
		User   string       `json:"https://vault/user"`
		Level1 GroupsLevel1 `json:"https"`
	}{
		"jeff",
		GroupsLevel1{
			GroupsLevel2{
				[]string{"foo", "bar"},
			},
		},
	}

	jwtData, _ := getTestJWT(t, privCA, cl, privateCl)

	data = map[string]interface{}{
		"role": "plugin-test",
		"jwt":  jwtData,
	}

	req = &logical.Request{
		Operation: logical.UpdateOperation,
		Path:      "login",
		Storage:   storage,
		Data:      data,
	}

	resp, err = b.HandleRequest(context.Background(), req)
	if err != nil {
		t.Fatal(err)
	}
	if resp == nil {
		t.Fatal("got nil response")
	}
	if resp.IsError() {
		t.Fatalf("got error: %v", resp.Error())
	}

	auth := resp.Auth
	switch {
	case len(auth.Policies) != 1 || auth.Policies[0] != "test":
		t.Fatal(auth.Policies)
	case auth.Alias.Name != "jeff":
		t.Fatal(auth.Alias.Name)
	case len(auth.GroupAliases) != 2 || auth.GroupAliases[0].Name != "foo" || auth.GroupAliases[1].Name != "bar":
		t.Fatal(auth.GroupAliases)
	case auth.Period != 3*time.Second:
		t.Fatal(auth.Period)
	case auth.TTL != time.Second:
		t.Fatal(auth.TTL)
	case auth.MaxTTL != 5*time.Second:
		t.Fatal(auth.MaxTTL)
	}
}

func validateTokenX5cChainClaims(rootCA string, token string) error {
	allClaims := map[string]interface{}{}
	claims := jwt.Claims{}

	parsedJWT, err := jwt.ParseSigned(token)
	if err != nil {
		return errors.Wrapf(err, "Unable to parse JWT token")
	}

	var validateKey interface{}
	var certClaims map[string]string
	validateKey, certClaims, err = validateCertChain([]byte(rootCA), parsedJWT)
	if err != nil {
		// If can't validate cert chain, use the rootCA public key
		validateKey = rootCA
	}

	if err := parsedJWT.Claims(validateKey, &claims, &allClaims); err == nil {
		if err := checkClaims(certClaims, allClaims); err != nil {
			return errors.New("Err: Claims don't match cert")
		}
		return nil
	} else {
		return err
	}
}

func TestTokenX5cChainClaims(t *testing.T) {
	if err := validateTokenX5cChainClaims(testTokenCert, testGoodToken); err != nil {
		t.Fatal("good token should pass chain check claim but failed")
	}
	if err := validateTokenX5cChainClaims(testTokenCert, testBadToken); err == nil {
		t.Fatal("bad token should not pass chain check claim but passed")
	}
}

const (
	pubCA string = `-----BEGIN CERTIFICATE-----
MIIDLDCCAhQCCQCMsgqQcWbl6DANBgkqhkiG9w0BAQUFADBYMQswCQYDVQQGEwJV
UzENMAsGA1UECAwEVGVzdDENMAsGA1UEBwwEVGVzdDENMAsGA1UECgwEVGVzdDEN
MAsGA1UECwwEVGVzdDENMAsGA1UEAwwEVGVzdDAeFw0xOTA0MDUxOTM0MzZaFw0x
OTA1MDUxOTM0MzZaMFgxCzAJBgNVBAYTAlVTMQ0wCwYDVQQIDARUZXN0MQ0wCwYD
VQQHDARUZXN0MQ0wCwYDVQQKDARUZXN0MQ0wCwYDVQQLDARUZXN0MQ0wCwYDVQQD
DARUZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAohwydHul+H2h
EBPgpBNWBisX2WyFyyP+95WsHAeKYf6cA/zucisEoqBgRXTWvtBDQTrsL5EgT07S
vIFzEDhHp/XMGFXbrRreWCxHIkqJVFl5ECByHclr/C6tg1OKAkXy2Nffcnp0W47X
HVgw1ZgodfzlCeGt4CLVJV2K60J/5gbnS3+zztMYCWzAoGRuClWMwEdaJC91eCe4
Jf8psYXrY/c394ZwU8o+U/m62ppMRtR9LQQXOyFrr9En7/jBfbXUJ3RuWIbHWcf/
ylVy057gT+N7O6OFOmnaBOllnj0nLBsDoeAAgZmB5dyN/GC3vv7kqqI36xncvaHM
5ntENo1x0wIDAQABMA0GCSqGSIb3DQEBBQUAA4IBAQCAt0+oa/zOwmz6Nj4jqyJ+
Gi/T9ofiUjJRPRT+krrJMNzD/8mknAM/GC/XeSFvs2A2ILNBMxkHUg2pKss3irNM
0A/UB5yYEDuTarSfmu/FbYhOLH4Ma9hKTl3z9qZhVuz0U+MMjWqJPncqAgzg4Buo
5P1Sde3Dsn+pUw2vZbopHtX/Kw0t/kr+y5nflpBIP9/sZOkAY+pLiK51E6kAs7H9
PNsY2yZtgtnr8DV00irC0aNa0AaxKUfYcAv+PQO2YIuxhC/UoBLgALf3ZHt8qs8g
Tn6K/ybUQ75vtlf9peNsOcTU3sZ+2Gdo0wdPwUQL9sWUXhqFRH6aRHeHhjmK5jjg
-----END CERTIFICATE-----`

	privCA string = `-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAohwydHul+H2hEBPgpBNWBisX2WyFyyP+95WsHAeKYf6cA/zu
cisEoqBgRXTWvtBDQTrsL5EgT07SvIFzEDhHp/XMGFXbrRreWCxHIkqJVFl5ECBy
Hclr/C6tg1OKAkXy2Nffcnp0W47XHVgw1ZgodfzlCeGt4CLVJV2K60J/5gbnS3+z
ztMYCWzAoGRuClWMwEdaJC91eCe4Jf8psYXrY/c394ZwU8o+U/m62ppMRtR9LQQX
OyFrr9En7/jBfbXUJ3RuWIbHWcf/ylVy057gT+N7O6OFOmnaBOllnj0nLBsDoeAA
gZmB5dyN/GC3vv7kqqI36xncvaHM5ntENo1x0wIDAQABAoIBAEqC4WIO72N/Awfr
ywY/aPve1NB4BCsx+WB9aCVeBeoy6C0hFcxeH3xMcNOb95SvDyqtVaAreYladpx0
d5nN9Imr/cp1tEolnmsytuN5FRQzJ+UUtL8iNMMuBUzmmfmfgxbOaoMo69CloBR5
08Bpdrd8rR3UoGH0QLoy+8ZUw4rLiD2ARi8thbnIcJrmTea34GYsV0vBvgoej9ZR
2tsx9YzrrtlkPNAmsvmoWgy5KLwGI0oFTF8Zs0Q1e0JCMaER78W/W+mmpcdT1e+s
Q4uvTCHYggnrPM0aGQurot0tG4oaj/G29woiN6CuA7HoKTtbgUsXgq6R7+SBHJqk
0cDYPmkCgYEAzhz5YunFuUjCnt4fi6dNdbOVGVJ33ODnULJVIGuA2VTyG46wqyzy
9V2cr1nHifkzpcs0kGJajL3CyeGZDGgfHHDDDVbqsfmuhyehp1XX4MHCjav8RQvQ
fWaZwNe8E6PjCrV2D6ND6IiWRES77bKqSUwYEMseBIq80LvHF7KvWScCgYEAyVi9
pNJtEF5RkwYa07Wyw6LxfImKB2Uy6KwfTi3In3l8r8ootIRR6smduruhjIGY/pwY
x8fFUAKdArVFl6s3gqkGtOc+HK8uZGv8wtTwbhF+KndYZUZppmd9dFgXkelN9SF8
1/eSnJyVNdK0QVzQPMaqMa3rl2tozd5+hy4KlXUCgYEAtXwZsxi4ev8wLwbSq/sy
X1MzE8rjs99sjkeYYSWHnNYJIG6x7Od1PsugrV3WLwz4hyG4NPIFXSuxmmVEiAIe
csJvXQ2NNgztuiARXPBfV44Eqw4m4P0YJXL0KzNKbdi+j61cOUS/BL9P4OjMuO26
tzODdTYERmeK/hh5o8o4T70CgYEAqHk1bdWY5qpVDXV9Owp9Aw+zimY3dYqq918W
br8GcNIhj6HTP4C8Xn3HGfln6n6COwD4BypUImedYye0jHz6XLz73KDlKvE2G1b0
Tz4H08GVVQk5kLxDKLbNlW0kg7W4wlT79mW0apDmlPuyUkLMBx6gSCNjzvZT4na6
Xnga6QUCgYEAtPKQEUGubc8HAobKyl+DvewRKeVxkGUS2LYVpGvlpGoaICccx3j8
f7I+AhBwwBf+6fSrvDep4BWw15uE+4rXMbs0b6H6lwgSxnqqZzRY5ybTQoYpr1yH
/hjzVraMJoZGjA34e2SrwBshCIKLZ1FzYhgHcerBxESGAfeP6Q3GnFA=
-----END RSA PRIVATE KEY-----`

	badPrivKey string = `-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAoXZFO1BBLZJ/MH3Kbri96EG3fZZYC45gmxRnN+YIm77QBzZf
To/om6tOSo+BaA6uQQaSazjKZ4WfoLBl5NtaibC/UkDQ1EQThnDIsADT976uw+e+
nMl79xBYu5BUo+pS3Ze/OY4XKMb8lYmQ2z8mKsKg/YYiQH88elYv+kMQ3BkSp3YY
8qe5IhxQOhUtAd/5nrB3gWwKSC4nsk7j1OkxvEhh871NPRhFnTJkJEllrhsEz4Ub
8+Z7n04WHFVDnF9d7nma10QGtZehuzBQyedOSJaZCI3oEn/icg1VGQ496amBmYiP
01Od6UetxX7gdRTA8qO5N80tIYGfzcC1cW2OZQIDAQABAoIBAQCchlhVSNb2w/cz
Xi7ZqZTIzLSCNjaCdXMnw97QbNtZiOCIrWg1dAMuriJG29m6s8iv1xwof7SQKRT3
pSoSc6fQpZzDs3v+20QGZ93V6eeTW7J2znmV6ymW+Kzcn+29vhK5KTvDIwFGkakZ
mnPoZ86rU2TYgalA11gczOLT/SIiC03UB6uVH4Mjoydfs7z6NuddXo4dk+8w34J0
w1GSUmmbflY8cbtwFPeRzEqJHIgEq7PXrpzx6cr9BkLqnX/i6BRwtil0myVjLbpW
qBerGkih6WPbyEuxot945r54PBxoWuuD6V7DdcxcVBsknftfXnB2b6KincXbiBPN
ifk6F0ehAoGBANTg41gVO5NEQ5Vgw2uWmAT0/8FMPZGaAMo6Ex8KStfFCGKckdVS
On3r2SIYm51R2Q+KYd6RJuei3+3IhCmvVgiRkX3FOyoOCE+8nDXbw1msEKVjG9zJ
Ih4kwGaHXWcU6eBG8/5Q/rcZ5Pc4Pmye33ulDO5WYSY2Nlb0IWjXAiuZAoGBAMIr
G94QFGgY5nx4ZlKpv9cWADz0Vg6jroviHGcKc9E9k0tYDm/jOZZcm1vmkmHX8PcM
rQO9Lmg8TKIVl9VZD5LXIMxrOycmGD3HAueFt/wW1e2hMqfYYjLeodJlRsAgpSIi
m1O3AoFNB03gh+wKW3x6am2yEiIYoQ+mdjuFtditAoGASs2fdZM4dP421WXEJaks
UAmbWVwmAmTgRC92CqE+PWXCFYy4/gHABgF7Miz9eaGKKZjR3TiaOCkWkOK19kPj
cm1cd5p3uMZni0VWiuJnWbpJuyQBZWrT702wwhZs7sz9hc7I7COf7c1OlMSRwu9s
znDoA1QdHSVNoO52UvXCkHkCgYA9e4kHd+/+RmQ1ZaqA4l9sq/rHUlctq4bJpH95
4UVrLCRH50orA7hodEp9fzU65jXXBJyEYpMfTni1mkDJvbnAtX4dPJcuflGOvkWd
KipoGJME+9Yeb9YoZXa4OHl+vNeNR4gHqhuQ9eMqNb7UbzMo51psAcbcJRBa9Erb
7ir2wQKBgAUy1rNY6x3QsAE2f6OYRC0TqLOrdHVDGH8awTMbfOcee2GfwBdtJd9c
jWtd4Snl/u9ziZ0dlAZyFzaytCABbMwMKIjlCzSLMCNZGDOjGyLtkaWzB+0HRZ3h
ZXGLmyl7eSc8ml5o8AZ6aJ2niou0NCJl4VgxJQstBzkFZR+eSL0Z
-----END RSA PRIVATE KEY-----`

	testTokenCert string = `-----BEGIN CERTIFICATE-----
MIIDXjCCAkagAwIBAgIUHj9PosLUQgguzgSpPNFFGrXSuvQwDQYJKoZIhvcNAQEL
BQAwIzEhMB8GA1UEAxMYdHJ1c3RlZC1pZGVudGl0eS5pYm0uY29tMB4XDTIwMDYw
NDEwMTY1MFoXDTIxMDYwNDEwMTcxOVowIzEhMB8GA1UEAxMYdHJ1c3RlZC1pZGVu
dGl0eS5pYm0uY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2MDI
DcxY00Ij37kEb7Lb+FvvYfoat24Ka5MPCONwMxvrJmbYNanYD/z7U6Nrjxca3f92
1NiHL5h0u0pdOH4IV27RTjJsmZDENq5jI90nlqogdKsP2nnJpXQguSewEIKA+XDf
ksnXG4j30LcH22hEO3qDZ8V6OFLJ1BPH/xsYd7bu+ygXsf6CHNWDzrq72IVLCc1A
YFR0GYOHhMSLryokAZhyvQ5mnJSKiey97HL9Mb29tMoWuVLyQJZiz9LAOZhgfcsq
1GGEkyCngfezwDZgrdXiCrZxrceuUZuKRpHUuTpi18ruYu+qYP/X0tIQT8GJdbSd
QZR/J/xraOKrigEzpwIDAQABo4GJMIGGMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMB
Af8EBTADAQH/MB0GA1UdDgQWBBTF+dvNkwIoez1/jaxwoAcowlmu/zAfBgNVHSME
GDAWgBTF+dvNkwIoez1/jaxwoAcowlmu/zAjBgNVHREEHDAaghh0cnVzdGVkLWlk
ZW50aXR5LmlibS5jb20wDQYJKoZIhvcNAQELBQADggEBAHm3ARlgloce5QRjaB+B
PPJzgC4pqdpbfi182nQtg9txl3RqYwCHGjtlT4sdsuVLVJF69aEvbPKtIzhwhc5O
jYg1YCEenS/dviwTk8Bbw38KEqH/jAD0ShVX+wyQl4odHveUq3dwx4hXzEOisOG3
TffIWXFSpNL0HC791w507VAJa6r+QvnKsQnn/NNr8wffpVG3Sybjnzix68HL9Rpo
HeAWk81YbbkJBwW4/Ea6iAeJYSDEOVcBU4Yvzk9KKuisVpk1KUAUO+GsuabxjKNj
Tx74wxpWPhg7TOtMqXIZYahlKCACTGAWJXzUVHwDmzU222n/tbj/c5cgJsEGno4Z
3YU=
-----END CERTIFICATE-----`
	testGoodToken string = `eyJhbGciOiJSUzI1NiIsImtpZCI6ImNNM0wyNnF5YVdZVWVya1c2Uzhpam1WS2ExVHE2dHR6dmxXOU1nelJhaFEiLCJ0eXAiOiJKV1QiLCJ4NWMiOlsiTUlJRGR6Q0NBbCtnQXdJQkFnSVVQRW9uaE1mSTNobXB4MlZNR0tJbVF5UjdKM1l3RFFZSktvWklodmNOQVFFTEJRQXdJekVoTUI4R0ExVUVBeE1ZZEhKMWMzUmxaQzFwWkdWdWRHbDBlUzVwWW0wdVkyOXRNQjRYRFRJd01EWXdOREV3TWpjME1Gb1hEVEl4TURZd05ERXdNamd4TUZvd0dURVhNQlVHQTFVRUF4TU9hbk56TFdwM2RDMXpaWEoyWlhJd2dnRWlNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0SUJEd0F3Z2dFS0FvSUJBUUM5NGNCNjNWWEFtZVpXOVAwNmNZVWp3Zld3N2xNU3Myc2JBN0N1MU53UDRMNG4wY0VhRXJGOWVhZllHdmorL09WSlQxR2ltR1VMU2UvbVRBT094WU9BNTlOWnMzUG9kQUhVcDZmSll6SlErSGNmUUVxUGJIUHJ1TmNCZUtXZEVxcHZyN0RRUEgxa1A3YUV6eG5RdGVjbzhGLzZMVGFWeHd6T2crSWxEdSt2UUgrZ0xxTjhCWEs2d3BHSnFKdnRCZXBQZkZoWStmUUwxQU9JVHJsUEgyRlFrWWlJTldwNmZFU1M1Y0tkcmhoTG1SWHlYQTd0ejBkdVhwQ0lWMHA1SXBnTlRPVzZVaHpOUjZhUVJNZkkwdEdJazE0N0tpek1JUithUVNEaFdkSVBSKy84dXcxV3F2RmJIeXNvdG15cTkwQUtrQzhualY4WVJxeTdqV1VGcTAvYkFnTUJBQUdqZ2F3d2dha3dEZ1lEVlIwUEFRSC9CQVFEQWdFR01BOEdBMVVkRXdFQi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZQekdFL2NyL2JrSlRUTDFhZHIvMzNrNnRLTWtNQjhHQTFVZEl3UVlNQmFBRk1YNTI4MlRBaWg3UFgrTnJIQ2dCeWpDV2E3L01FWUdBMVVkRVFRL01EMkNEbXB6Y3kxcWQzUXRjMlZ5ZG1WeWhobDBjMms2WTJ4MWMzUmxjaTF1WVcxbE9uUnBMWFJsYzNReGhoQjBjMms2Y21WbmFXOXVPbVYxTFdSbE1BMEdDU3FHU0liM0RRRUJDd1VBQTRJQkFRRFYzN0dMR2pPand6WFpHU01qN1U1L0oxZnlvUjFTK1pHU1ZWSWExWHpyQWdrYlExUk8rK1BmdldNTk5TMXVGU21hbHI4V0RNU3VuV1dDSUc5Q3BwQmlaaEI4bm9hRW1KZjV4YUVtOG56L1ZMcGk4ekdyOWRnaUlCNjlzMG9mWEl3MlpwdzFLTFdTOEpMOVZ3QmZtZ0RMMDdIaXFzUSt3WWVzK2Vta1ZuMmd5enJNQjJjUzM4TUtVM3R0eHB4bUpkSVVOZTV3K21hV1lNa1hDN28xWGxPU0hCSnJBazJVZThRWjg4VE1uNGZzMkI4VklEUnFhcXFDUGxoZzYyMzIxOG1Gd2I3K0hkVFp1R0ZpWFpDMjUxOThCaFo4Y05IaXZLeW92dklWZ2RsN254L2crd1NOaXNvRXprcytOME1QMHFISncrenRRaGNhUUNBeUpodkZUZHJrIiwiTUlJRFhqQ0NBa2FnQXdJQkFnSVVIajlQb3NMVVFnZ3V6Z1NwUE5GRkdyWFN1dlF3RFFZSktvWklodmNOQVFFTEJRQXdJekVoTUI4R0ExVUVBeE1ZZEhKMWMzUmxaQzFwWkdWdWRHbDBlUzVwWW0wdVkyOXRNQjRYRFRJd01EWXdOREV3TVRZMU1Gb1hEVEl4TURZd05ERXdNVGN4T1Zvd0l6RWhNQjhHQTFVRUF4TVlkSEoxYzNSbFpDMXBaR1Z1ZEdsMGVTNXBZbTB1WTI5dE1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBMk1ESURjeFkwMElqMzdrRWI3TGIrRnZ2WWZvYXQyNEthNU1QQ09Od014dnJKbWJZTmFuWUQvejdVNk5yanhjYTNmOTIxTmlITDVoMHUwcGRPSDRJVjI3UlRqSnNtWkRFTnE1akk5MG5scW9nZEtzUDJubkpwWFFndVNld0VJS0ErWERma3NuWEc0ajMwTGNIMjJoRU8zcURaOFY2T0ZMSjFCUEgveHNZZDdidSt5Z1hzZjZDSE5XRHpycTcySVZMQ2MxQVlGUjBHWU9IaE1TTHJ5b2tBWmh5dlE1bW5KU0tpZXk5N0hMOU1iMjl0TW9XdVZMeVFKWml6OUxBT1poZ2Zjc3ExR0dFa3lDbmdmZXp3RFpncmRYaUNyWnhyY2V1VVp1S1JwSFV1VHBpMThydVl1K3FZUC9YMHRJUVQ4R0pkYlNkUVpSL0oveHJhT0tyaWdFenB3SURBUUFCbzRHSk1JR0dNQTRHQTFVZER3RUIvd1FFQXdJQkJqQVBCZ05WSFJNQkFmOEVCVEFEQVFIL01CMEdBMVVkRGdRV0JCVEYrZHZOa3dJb2V6MS9qYXh3b0Fjb3dsbXUvekFmQmdOVkhTTUVHREFXZ0JURitkdk5rd0lvZXoxL2pheHdvQWNvd2xtdS96QWpCZ05WSFJFRUhEQWFnaGgwY25WemRHVmtMV2xrWlc1MGFYUjVMbWxpYlM1amIyMHdEUVlKS29aSWh2Y05BUUVMQlFBRGdnRUJBSG0zQVJsZ2xvY2U1UVJqYUIrQlBQSnpnQzRwcWRwYmZpMTgyblF0Zzl0eGwzUnFZd0NIR2p0bFQ0c2RzdVZMVkpGNjlhRXZiUEt0SXpod2hjNU9qWWcxWUNFZW5TL2R2aXdUazhCYnczOEtFcUgvakFEMFNoVlgrd3lRbDRvZEh2ZVVxM2R3eDRoWHpFT2lzT0czVGZmSVdYRlNwTkwwSEM3OTF3NTA3VkFKYTZyK1F2bktzUW5uL05Ocjh3ZmZwVkczU3liam56aXg2OEhMOVJwb0hlQVdrODFZYmJrSkJ3VzQvRWE2aUFlSllTREVPVmNCVTRZdnprOUtLdWlzVnBrMUtVQVVPK0dzdWFieGpLTmpUeDc0d3hwV1BoZzdUT3RNcVhJWllhaGxLQ0FDVEdBV0pYelVWSHdEbXpVMjIybi90YmovYzVjZ0pzRUdubzRaM1lVPSJdfQ.eyJjbHVzdGVyLW5hbWUiOiJ0aS10ZXN0MSIsImV4cCI6MjU5MTI2NzU4NCwiaWF0IjoxNTkxMjY3NTg1LCJpbWFnZXMiOiIzMGJlZWQwNjY1ZDljYjRkZjYxNmNjYTg0ZWYyYzA2ZDIzMjNlMDI4NjlmY2NhOGJiZmJmMGQ4YzVhMzk4N2NjIiwiaW1hZ2VzLW5hbWVzIjoidWJ1bnR1QHNoYTI1NjoyNTBjYzZmM2YzZmZjNWNkYWE5ZDhmNDk0NmFjNzk4MjFhYWZiNGQzYWZjOTM5MjhmMGRlOTMzNmViYTIxYWE0IiwiaXNzIjoid3NjaGVkQHVzLmlibS5jb20iLCJtYWNoaW5laWQiOiJiNDZlMTY1YzMyZDM0MmQ5ODk2ZDllZWI0M2M0ZDVkZCIsIm5hbWVzcGFjZSI6InRlc3QiLCJwb2QiOiJteXVidW50dS02NzU2ZDY2NWJjLWdjMjVmIiwicmVnaW9uIjoiZXUtZGUiLCJzdWIiOiJ3c2NoZWRAdXMuaWJtLmNvbSJ9.Vbc1LT2PzbWZShq9wFeXyN4OhrcY1PAM2pOm5jlAajiunyr9Rxy_bIFyNzebuY5LIp21Yx5dgZkLuIttgmQ0-D314C60Y-jlLiKpS4PX4uXSjuBRcSWOaGT2Ksmjqe5M9hcUzscdXItVjsA8PJV9T9eVxHzbUaZLpNRGVtjX3fP7eAeSwSCmxxwm674XDIO-1HFCWho1EVvLIJhI9DK120gIG2_6Oyiea02gD7Nby_WZQObdZ0KEXfo9amsTDAkxwnm3T4tBDvF8qUYyBqbLnfOiQ-lOiNA3BmrtoYOh241pBwK9Z-7Xm0aE1f_l4jv417L7XpIpy039xFYY0FH87g`

	testBadToken string = `eyJhbGciOiJSUzI1NiIsImtpZCI6ImNNM0wyNnF5YVdZVWVya1c2Uzhpam1WS2ExVHE2dHR6dmxXOU1nelJhaFEiLCJ0eXAiOiJKV1QiLCJ4NWMiOlsiTUlJRGR6Q0NBbCtnQXdJQkFnSVVQRW9uaE1mSTNobXB4MlZNR0tJbVF5UjdKM1l3RFFZSktvWklodmNOQVFFTEJRQXdJekVoTUI4R0ExVUVBeE1ZZEhKMWMzUmxaQzFwWkdWdWRHbDBlUzVwWW0wdVkyOXRNQjRYRFRJd01EWXdOREV3TWpjME1Gb1hEVEl4TURZd05ERXdNamd4TUZvd0dURVhNQlVHQTFVRUF4TU9hbk56TFdwM2RDMXpaWEoyWlhJd2dnRWlNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0SUJEd0F3Z2dFS0FvSUJBUUM5NGNCNjNWWEFtZVpXOVAwNmNZVWp3Zld3N2xNU3Myc2JBN0N1MU53UDRMNG4wY0VhRXJGOWVhZllHdmorL09WSlQxR2ltR1VMU2UvbVRBT094WU9BNTlOWnMzUG9kQUhVcDZmSll6SlErSGNmUUVxUGJIUHJ1TmNCZUtXZEVxcHZyN0RRUEgxa1A3YUV6eG5RdGVjbzhGLzZMVGFWeHd6T2crSWxEdSt2UUgrZ0xxTjhCWEs2d3BHSnFKdnRCZXBQZkZoWStmUUwxQU9JVHJsUEgyRlFrWWlJTldwNmZFU1M1Y0tkcmhoTG1SWHlYQTd0ejBkdVhwQ0lWMHA1SXBnTlRPVzZVaHpOUjZhUVJNZkkwdEdJazE0N0tpek1JUithUVNEaFdkSVBSKy84dXcxV3F2RmJIeXNvdG15cTkwQUtrQzhualY4WVJxeTdqV1VGcTAvYkFnTUJBQUdqZ2F3d2dha3dEZ1lEVlIwUEFRSC9CQVFEQWdFR01BOEdBMVVkRXdFQi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZQekdFL2NyL2JrSlRUTDFhZHIvMzNrNnRLTWtNQjhHQTFVZEl3UVlNQmFBRk1YNTI4MlRBaWg3UFgrTnJIQ2dCeWpDV2E3L01FWUdBMVVkRVFRL01EMkNEbXB6Y3kxcWQzUXRjMlZ5ZG1WeWhobDBjMms2WTJ4MWMzUmxjaTF1WVcxbE9uUnBMWFJsYzNReGhoQjBjMms2Y21WbmFXOXVPbVYxTFdSbE1BMEdDU3FHU0liM0RRRUJDd1VBQTRJQkFRRFYzN0dMR2pPand6WFpHU01qN1U1L0oxZnlvUjFTK1pHU1ZWSWExWHpyQWdrYlExUk8rK1BmdldNTk5TMXVGU21hbHI4V0RNU3VuV1dDSUc5Q3BwQmlaaEI4bm9hRW1KZjV4YUVtOG56L1ZMcGk4ekdyOWRnaUlCNjlzMG9mWEl3MlpwdzFLTFdTOEpMOVZ3QmZtZ0RMMDdIaXFzUSt3WWVzK2Vta1ZuMmd5enJNQjJjUzM4TUtVM3R0eHB4bUpkSVVOZTV3K21hV1lNa1hDN28xWGxPU0hCSnJBazJVZThRWjg4VE1uNGZzMkI4VklEUnFhcXFDUGxoZzYyMzIxOG1Gd2I3K0hkVFp1R0ZpWFpDMjUxOThCaFo4Y05IaXZLeW92dklWZ2RsN254L2crd1NOaXNvRXprcytOME1QMHFISncrenRRaGNhUUNBeUpodkZUZHJrIiwiTUlJRFhqQ0NBa2FnQXdJQkFnSVVIajlQb3NMVVFnZ3V6Z1NwUE5GRkdyWFN1dlF3RFFZSktvWklodmNOQVFFTEJRQXdJekVoTUI4R0ExVUVBeE1ZZEhKMWMzUmxaQzFwWkdWdWRHbDBlUzVwWW0wdVkyOXRNQjRYRFRJd01EWXdOREV3TVRZMU1Gb1hEVEl4TURZd05ERXdNVGN4T1Zvd0l6RWhNQjhHQTFVRUF4TVlkSEoxYzNSbFpDMXBaR1Z1ZEdsMGVTNXBZbTB1WTI5dE1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBMk1ESURjeFkwMElqMzdrRWI3TGIrRnZ2WWZvYXQyNEthNU1QQ09Od014dnJKbWJZTmFuWUQvejdVNk5yanhjYTNmOTIxTmlITDVoMHUwcGRPSDRJVjI3UlRqSnNtWkRFTnE1akk5MG5scW9nZEtzUDJubkpwWFFndVNld0VJS0ErWERma3NuWEc0ajMwTGNIMjJoRU8zcURaOFY2T0ZMSjFCUEgveHNZZDdidSt5Z1hzZjZDSE5XRHpycTcySVZMQ2MxQVlGUjBHWU9IaE1TTHJ5b2tBWmh5dlE1bW5KU0tpZXk5N0hMOU1iMjl0TW9XdVZMeVFKWml6OUxBT1poZ2Zjc3ExR0dFa3lDbmdmZXp3RFpncmRYaUNyWnhyY2V1VVp1S1JwSFV1VHBpMThydVl1K3FZUC9YMHRJUVQ4R0pkYlNkUVpSL0oveHJhT0tyaWdFenB3SURBUUFCbzRHSk1JR0dNQTRHQTFVZER3RUIvd1FFQXdJQkJqQVBCZ05WSFJNQkFmOEVCVEFEQVFIL01CMEdBMVVkRGdRV0JCVEYrZHZOa3dJb2V6MS9qYXh3b0Fjb3dsbXUvekFmQmdOVkhTTUVHREFXZ0JURitkdk5rd0lvZXoxL2pheHdvQWNvd2xtdS96QWpCZ05WSFJFRUhEQWFnaGgwY25WemRHVmtMV2xrWlc1MGFYUjVMbWxpYlM1amIyMHdEUVlKS29aSWh2Y05BUUVMQlFBRGdnRUJBSG0zQVJsZ2xvY2U1UVJqYUIrQlBQSnpnQzRwcWRwYmZpMTgyblF0Zzl0eGwzUnFZd0NIR2p0bFQ0c2RzdVZMVkpGNjlhRXZiUEt0SXpod2hjNU9qWWcxWUNFZW5TL2R2aXdUazhCYnczOEtFcUgvakFEMFNoVlgrd3lRbDRvZEh2ZVVxM2R3eDRoWHpFT2lzT0czVGZmSVdYRlNwTkwwSEM3OTF3NTA3VkFKYTZyK1F2bktzUW5uL05Ocjh3ZmZwVkczU3liam56aXg2OEhMOVJwb0hlQVdrODFZYmJrSkJ3VzQvRWE2aUFlSllTREVPVmNCVTRZdnprOUtLdWlzVnBrMUtVQVVPK0dzdWFieGpLTmpUeDc0d3hwV1BoZzdUT3RNcVhJWllhaGxLQ0FDVEdBV0pYelVWSHdEbXpVMjIybi90YmovYzVjZ0pzRUdubzRaM1lVPSJdfQ.eyJjbHVzdGVyLW5hbWUiOiJ0aS10ZXN0MSIsImV4cCI6MjU5MTI2Nzc3MiwiaWF0IjoxNTkxMjY3NzczLCJpbWFnZXMiOiIzMGJlZWQwNjY1ZDljYjRkZjYxNmNjYTg0ZWYyYzA2ZDIzMjNlMDI4NjlmY2NhOGJiZmJmMGQ4YzVhMzk4N2NjIiwiaW1hZ2VzLW5hbWVzIjoidWJ1bnR1QHNoYTI1NjoyNTBjYzZmM2YzZmZjNWNkYWE5ZDhmNDk0NmFjNzk4MjFhYWZiNGQzYWZjOTM5MjhmMGRlOTMzNmViYTIxYWE0IiwiaXNzIjoid3NjaGVkQHVzLmlibS5jb20iLCJtYWNoaW5laWQiOiJiNDZlMTY1YzMyZDM0MmQ5ODk2ZDllZWI0M2M0ZDVkZCIsIm5hbWVzcGFjZSI6InRlc3QiLCJwb2QiOiJteXVidW50dS02NzU2ZDY2NWJjLWdjMjVmIiwicmVnaW9uIjoidXMtc291dGgiLCJzdWIiOiJ3c2NoZWRAdXMuaWJtLmNvbSJ9.OseuzX5mltScVZ-K9BZKMeiSkL_0iYHFWBnZ5uotwYOQiw0LWTd-nwNlE-in5mLsS3TNLcNDFZSxgia3EyRUpBrpBx56l4b3kJa7GEm82h_ELjdDm8hVq_lifU5X4y3PhRO69P9dVV1IeolOHR_LLi6s6ubhj8TP7y5Q-JmqHw-v8Why9P32LGvdWEgmDC5kvTizpGddK5xTzmlFc-1REryXUtPTBgrWczmh1Sj9ABaeWMDASc-hO8zDZhsYCqnd6A6YlBk63BmUa2weLRjiFfifxL8IcKU0Ektf4T8poysdfnRydPxAhuvDBhmVHvwa2fM2CNEtmGTjTDNxe2Giqw`
)
