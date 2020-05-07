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
MIIDCDCCAfCgAwIBAgIJAI8ECOEbEYGjMA0GCSqGSIb3DQEBBQUAMBcxFTATBgNV
BAMMDHZhdWx0LXNlcnZlcjAeFw0yMDA1MDQxNDUzMzNaFw0yMDA2MDMxNDUzMzNa
MBkxFzAVBgNVBAMMDmpzcy1qd3Qtc2VydmVyMIIBIjANBgkqhkiG9w0BAQEFAAOC
AQ8AMIIBCgKCAQEA6Ei0+AcignaBWnRzAlj9dkVlbDkZ+Z0DeCvA35yN+Oz/h3HC
tKIUr13uJXBzHt4cfKuPQzB5hTvHAPz7KDafkcVFOrvAmB145bypJ0u4Lyi3GNDx
9DKCtfE8G+JGfJeyiS8kt2TRI2JHBiZRiOH6DZWUcjX9XAgCA2+C+7fXDK6yb3LS
JaqavCv0RDTlDtWe0qbS+50akUkoqYeKpwOi5WMuLMjZBn1nlyY5wBY7i4SHLrnr
xHujf5egEaP31lgDM+L3iXYXUEJYvWzwVOQrMrvdM/6zv55fHEq5hDKuWlln6aAA
/R0bsmA7aPQhFrJ3mbgq/OPZLU6zRyxT1ajY6QIDAQABo1UwUzBRBgNVHREESjBI
hhpUU0k6Y2x1c3Rlci1uYW1lOm15Y2x1c3RlcoYUVFNJOnJlZ2lvbk5hbWU6ZXUt
ZGWGFFRTSTpkYXRhY2VudGVyOmZyYTAyMA0GCSqGSIb3DQEBBQUAA4IBAQBfyKhB
1XGzA99jYpPxV+m7y5IvAuLjVIFyM0zyW1ZRMBj/NfW2NJWaO+4qthqN6ByjmhIl
Q1drYDI7pvkflvL+5ZCWMLUWrftz670i5zNuHdGavk+LbLiKTzfBdqkr6agB5oug
VVwWQ11TvJms4YEVz8t5HKkIqvn9gKq1BaWcOnG+VSn5zLrl9CuzH3eKEJDOrd50
Q0C+xfB7Ikkhh/AiQt/PmYx1pJZUqxg90+7ndHVExh8y3VHWKFqaiN30ZfRdjIjc
2kzKQ5QaslWMP1m/TepCkrvG6KonJ6T4xAVSmMWSlNNCSOOCp2EfYdFjytWmanWc
Y1sgysDkYs5ztN2W
-----END CERTIFICATE-----`

	testGoodToken string = `eyJhbGciOiJSUzI1NiIsImtpZCI6Im9FczYwZmFPbkNFWGtEa0hLamt1TTV2aXRnZG5yZTVlVnN6VzcyOUw0MmciLCJ0eXAiOiJKV1QiLCJ4NWMiOlsiTUlJRENEQ0NBZkNnQXdJQkFnSUpBSThFQ09FYkVZR2pNQTBHQ1NxR1NJYjNEUUVCQlFVQU1CY3hGVEFUQmdOVkJBTU1ESFpoZFd4MExYTmxjblpsY2pBZUZ3MHlNREExTURReE5EVXpNek5hRncweU1EQTJNRE14TkRVek16TmFNQmt4RnpBVkJnTlZCQU1NRG1wemN5MXFkM1F0YzJWeWRtVnlNSUlCSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DQVE4QU1JSUJDZ0tDQVFFQTZFaTArQWNpZ25hQlduUnpBbGo5ZGtWbGJEa1orWjBEZUN2QTM1eU4rT3ovaDNIQ3RLSVVyMTN1SlhCekh0NGNmS3VQUXpCNWhUdkhBUHo3S0RhZmtjVkZPcnZBbUIxNDVieXBKMHU0THlpM0dORHg5REtDdGZFOEcrSkdmSmV5aVM4a3QyVFJJMkpIQmlaUmlPSDZEWldVY2pYOVhBZ0NBMitDKzdmWERLNnliM0xTSmFxYXZDdjBSRFRsRHRXZTBxYlMrNTBha1Vrb3FZZUtwd09pNVdNdUxNalpCbjFubHlZNXdCWTdpNFNITHJucnhIdWpmNWVnRWFQMzFsZ0RNK0wzaVhZWFVFSll2V3p3Vk9Rck1ydmRNLzZ6djU1ZkhFcTVoREt1V2xsbjZhQUEvUjBic21BN2FQUWhGckozbWJncS9PUFpMVTZ6Unl4VDFhalk2UUlEQVFBQm8xVXdVekJSQmdOVkhSRUVTakJJaGhwVVUwazZZMngxYzNSbGNpMXVZVzFsT20xNVkyeDFjM1JsY29ZVVZGTkpPbkpsWjJsdmJrNWhiV1U2WlhVdFpHV0dGRlJUU1Rwa1lYUmhZMlZ1ZEdWeU9tWnlZVEF5TUEwR0NTcUdTSWIzRFFFQkJRVUFBNElCQVFCZnlLaEIxWEd6QTk5allwUHhWK203eTVJdkF1TGpWSUZ5TTB6eVcxWlJNQmovTmZXMk5KV2FPKzRxdGhxTjZCeWptaElsUTFkcllESTdwdmtmbHZMKzVaQ1dNTFVXcmZ0ejY3MGk1ek51SGRHYXZrK0xiTGlLVHpmQmRxa3I2YWdCNW91Z1ZWd1dRMTFUdkptczRZRVZ6OHQ1SEtrSXF2bjlnS3ExQmFXY09uRytWU241ekxybDlDdXpIM2VLRUpET3JkNTBRMEMreGZCN0lra2hoL0FpUXQvUG1ZeDFwSlpVcXhnOTArN25kSFZFeGg4eTNWSFdLRnFhaU4zMFpmUmRqSWpjMmt6S1E1UWFzbFdNUDFtL1RlcENrcnZHNktvbko2VDR4QVZTbU1XU2xOTkNTT09DcDJFZllkRmp5dFdtYW5XY1kxc2d5c0RrWXM1enROMlciLCJNSUlDcWpDQ0FaSUNDUUNoUEovcDZwTUNpVEFOQmdrcWhraUc5dzBCQVFzRkFEQVhNUlV3RXdZRFZRUUREQXgyWVhWc2RDMXpaWEoyWlhJd0hoY05NakF3TlRBME1UUTFNak0xV2hjTk1qQXdOakF6TVRRMU1qTTFXakFYTVJVd0V3WURWUVFEREF4MllYVnNkQzF6WlhKMlpYSXdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFDN3hVeHB3UzgwdFNxdENzQ0RTZ1NjNmJTNGdDbEhMWTZJQUdkNGROdVZBdlMydzlnUm1SUzUrZWJrOEppQmZMbGtKWDZDOUZpcldoUm5rTmo2K1RtUmcrdzhpdERwV2k3UFpYY0VoK3U4Z2dqNHBnM0g5VFQ5dFdOempKOCtuQUlUVDdIczR1ck9kbHBrSlFQZjBlZURjQStHd3QySjE1MGRIQWNDQmc5SnQ2T0QrSVJTUUFhODRoN3lKdVpFWjl2Zm0xMGpqZXpjeitqUlVVaVorTmhNL0xnVWFLcjQybm96bE9ybGkvditzYlFkZDh4RnZVUUJsVDFRRUhaTUlydFl1NUFKOG1TQ0poSGQ1ZHZ2VmowVzh1Vmw3M0RYdWZTM3dKS2tzRlhYemVpa1NFTUY0bUY0YjUyOWlFNVIyb0Z1MlRxSFc5Um5TakhreW5WOVN1VGJBZ01CQUFFd0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFLTmVjbFhvWTZxazRtbkFRZzdWZWtaZHViRU1YbnZGL01OdVd3NXBrMlcrZWZrRGl3ZmJHOVBqN3lIa2dsZGlZWFovQWFBZkhTR1hHQUlWeUtRcGtaOVc0TGRCeStSUFRRbWxOUHlzM1JJQWtJMFVSRDc4Sjk0dlBObjNnVE5xa2tpMEpVSCtnMUFBcmFCcWMzNVprVmJpQmsxNWNLdHA1SVpXeDV4SkxUSU1tcE93RUx3NHVuR3ZHU0JBWFRkV1JralRpVjVuVVNMSXVHMzBTMWxaOVdhTHNKRFdpTDFGRWxpNFpaM2dBcW9FeVNnS2RrTU5jOWhtRnZFNTd6N21yNmFvZitoVTN5QkRpQkt2ajNiNGl2RGVLNjNqMThKWHB4VDZnKzFBR2VyUnRnT1RPLzFneWRRR2dqeEJZeFBRWWJ5OGR4V1VwN3dyQjFlVW45OS9jc2c9Il19.                                                                                                                                                                           eyJjbHVzdGVyLW5hbWUiOiJteWNsdXN0ZXIiLCJkYXRhY2VudGVyIjoiZnJhMDIiLCJyZWdpb25OYW1lIjoiZXUtZGUiLCJleHAiOjE1ODgyODExNzcsImlhdCI6MTU4ODI4MTExNywiaW1hZ2VzIjoiMzBiZWVkMDY2NWQ5Y2I0ZGY2MTZjY2E4NGVmMmMwNmQyMzIzZTAyODY5ZmNjYThiYmZiZjBkOGM1YTM5ODdjYyIsImltYWdlcy1uYW1lcyI6InVidW50dUBzaGEyNTY6MjUwY2M2ZjNmM2ZmYzVjZGFhOWQ4ZjQ5NDZhYzc5ODIxYWFmYjRkM2FmYzkzOTI4ZjBkZTkzMzZlYmEyMWFhNCIsImlzcyI6IndzY2hlZEB1cy5pYm0uY29tIiwibWFjaGluZWlkIjoiYjQ2ZTE2NWMzMmQzNDJkOTg5NmQ5ZWViNDNjNGQ1ZGQiLCJuYW1lc3BhY2UiOiJ0ZXN0IiwicG9kIjoibXl1YnVudHUtNjc1NmQ2NjViYy1tMmp6NiIsInN1YiI6IndzY2hlZEB1cy5pYm0uY29tIn0.Yy_nTzLWmxDMCCq1TOfiHLMU9SFAIPv1ahxRHcbnn6tCOVVp1E13zKSZtoUajBFaj0CefgokpBnUipIpzcvZX4XeBy6--t6DR7Epd5RWDryj7tcIh_ShsK00V7PKeF4JvGhq15iDhKHNIYBbSzwLNBDhbyARzlFE1tszjKcUeBiZf7zvQ8C0SjISjtDE4f-                                                                   dvnquTI62P8nhYqQXiiTpjIhKbgdHECxbdgVgLgfwHdxbkiBiqOodijikS0TjgkC5iUBGDWZvhbQLq8OCVThZoM09aT4gIE5PnBMRJXhAUkzS39lKvQNCONiVGkNvwVCqK3LLffVfe3vQy3aNiKXTUw`

	testBadToken string = `eyJhbGciOiJSUzI1NiIsImtpZCI6Im9FczYwZmFPbkNFWGtEa0hLamt1TTV2aXRnZG5yZTVlVnN6VzcyOUw0MmciLCJ0eXAiOiJKV1QiLCJ4NWMiOlsiTUlJRENEQ0NBZkNnQXdJQkFnSUpBSThFQ09FYkVZR2pNQTBHQ1NxR1NJYjNEUUVCQlFVQU1CY3hGVEFUQmdOVkJBTU1ESFpoZFd4MExYTmxjblpsY2pBZUZ3MHlNREExTURReE5EVXpNek5hRncweU1EQTJNRE14TkRVek16TmFNQmt4RnpBVkJnTlZCQU1NRG1wemN5MXFkM1F0YzJWeWRtVnlNSUlCSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DQVE4QU1JSUJDZ0tDQVFFQTZFaTArQWNpZ25hQlduUnpBbGo5ZGtWbGJEa1orWjBEZUN2QTM1eU4rT3ovaDNIQ3RLSVVyMTN1SlhCekh0NGNmS3VQUXpCNWhUdkhBUHo3S0RhZmtjVkZPcnZBbUIxNDVieXBKMHU0THlpM0dORHg5REtDdGZFOEcrSkdmSmV5aVM4a3QyVFJJMkpIQmlaUmlPSDZEWldVY2pYOVhBZ0NBMitDKzdmWERLNnliM0xTSmFxYXZDdjBSRFRsRHRXZTBxYlMrNTBha1Vrb3FZZUtwd09pNVdNdUxNalpCbjFubHlZNXdCWTdpNFNITHJucnhIdWpmNWVnRWFQMzFsZ0RNK0wzaVhZWFVFSll2V3p3Vk9Rck1ydmRNLzZ6djU1ZkhFcTVoREt1V2xsbjZhQUEvUjBic21BN2FQUWhGckozbWJncS9PUFpMVTZ6Unl4VDFhalk2UUlEQVFBQm8xVXdVekJSQmdOVkhSRUVTakJJaGhwVVUwazZZMngxYzNSbGNpMXVZVzFsT20xNVkyeDFjM1JsY29ZVVZGTkpPbkpsWjJsdmJrNWhiV1U2WlhVdFpHV0dGRlJUU1Rwa1lYUmhZMlZ1ZEdWeU9tWnlZVEF5TUEwR0NTcUdTSWIzRFFFQkJRVUFBNElCQVFCZnlLaEIxWEd6QTk5allwUHhWK203eTVJdkF1TGpWSUZ5TTB6eVcxWlJNQmovTmZXMk5KV2FPKzRxdGhxTjZCeWptaElsUTFkcllESTdwdmtmbHZMKzVaQ1dNTFVXcmZ0ejY3MGk1ek51SGRHYXZrK0xiTGlLVHpmQmRxa3I2YWdCNW91Z1ZWd1dRMTFUdkptczRZRVZ6OHQ1SEtrSXF2bjlnS3ExQmFXY09uRytWU241ekxybDlDdXpIM2VLRUpET3JkNTBRMEMreGZCN0lra2hoL0FpUXQvUG1ZeDFwSlpVcXhnOTArN25kSFZFeGg4eTNWSFdLRnFhaU4zMFpmUmRqSWpjMmt6S1E1UWFzbFdNUDFtL1RlcENrcnZHNktvbko2VDR4QVZTbU1XU2xOTkNTT09DcDJFZllkRmp5dFdtYW5XY1kxc2d5c0RrWXM1enROMlciLCJNSUlDcWpDQ0FaSUNDUUNoUEovcDZwTUNpVEFOQmdrcWhraUc5dzBCQVFzRkFEQVhNUlV3RXdZRFZRUUREQXgyWVhWc2RDMXpaWEoyWlhJd0hoY05NakF3TlRBME1UUTFNak0xV2hjTk1qQXdOakF6TVRRMU1qTTFXakFYTVJVd0V3WURWUVFEREF4MllYVnNkQzF6WlhKMlpYSXdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFDN3hVeHB3UzgwdFNxdENzQ0RTZ1NjNmJTNGdDbEhMWTZJQUdkNGROdVZBdlMydzlnUm1SUzUrZWJrOEppQmZMbGtKWDZDOUZpcldoUm5rTmo2K1RtUmcrdzhpdERwV2k3UFpYY0VoK3U4Z2dqNHBnM0g5VFQ5dFdOempKOCtuQUlUVDdIczR1ck9kbHBrSlFQZjBlZURjQStHd3QySjE1MGRIQWNDQmc5SnQ2T0QrSVJTUUFhODRoN3lKdVpFWjl2Zm0xMGpqZXpjeitqUlVVaVorTmhNL0xnVWFLcjQybm96bE9ybGkvditzYlFkZDh4RnZVUUJsVDFRRUhaTUlydFl1NUFKOG1TQ0poSGQ1ZHZ2VmowVzh1Vmw3M0RYdWZTM3dKS2tzRlhYemVpa1NFTUY0bUY0YjUyOWlFNVIyb0Z1MlRxSFc5Um5TakhreW5WOVN1VGJBZ01CQUFFd0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFLTmVjbFhvWTZxazRtbkFRZzdWZWtaZHViRU1YbnZGL01OdVd3NXBrMlcrZWZrRGl3ZmJHOVBqN3lIa2dsZGlZWFovQWFBZkhTR1hHQUlWeUtRcGtaOVc0TGRCeStSUFRRbWxOUHlzM1JJQWtJMFVSRDc4Sjk0dlBObjNnVE5xa2tpMEpVSCtnMUFBcmFCcWMzNVprVmJpQmsxNWNLdHA1SVpXeDV4SkxUSU1tcE93RUx3NHVuR3ZHU0JBWFRkV1JralRpVjVuVVNMSXVHMzBTMWxaOVdhTHNKRFdpTDFGRWxpNFpaM2dBcW9FeVNnS2RrTU5jOWhtRnZFNTd6N21yNmFvZitoVTN5QkRpQkt2ajNiNGl2RGVLNjNqMThKWHB4VDZnKzFBR2VyUnRnT1RPLzFneWRRR2dqeEJZeFBRWWJ5OGR4V1VwN3dyQjFlVW45OS9jc2c9Il19.                                                                                                                                                                           eyJjbHVzdGVyLW5hbWUiOiJteWNsdXN0ZXIiLCJkYXRhY2VudGVyIjoiZGFsMDUiLCJyZWdpb25OYW1lIjoidXMtZWFzdCIsImV4cCI6MTU4ODI4MTE3NywiaWF0IjoxNTg4MjgxMTE3LCJpbWFnZXMiOiIzMGJlZWQwNjY1ZDljYjRkZjYxNmNjYTg0ZWYyYzA2ZDIzMjNlMDI4NjlmY2NhOGJiZmJmMGQ4YzVhMzk4N2NjIiwiaW1hZ2VzLW5hbWVzIjoidWJ1bnR1QHNoYTI1NjoyNTBjYzZmM2YzZmZjNWNkYWE5ZDhmNDk0NmFjNzk4MjFhYWZiNGQzYWZjOTM5MjhmMGRlOTMzNmViYTIxYWE0IiwiaXNzIjoid3NjaGVkQHVzLmlibS5jb20iLCJtYWNoaW5laWQiOiJiNDZlMTY1YzMyZDM0MmQ5ODk2ZDllZWI0M2M0ZDVkZCIsIm5hbWVzcGFjZSI6InRlc3QiLCJwb2QiOiJteXVidW50dS02NzU2ZDY2NWJjLW0yano2Iiwic3ViIjoid3NjaGVkQHVzLmlibS5jb20ifQ.X5ECXRbjMKapelN-O7zmqvfdVTMtm2G7RdIjWpWnAcOpz9WrsCFCZdJ4KoeT_AF7DFTJVdh6-VhEqu2ezsZz6nI6CPnZFzm68O4Yr2LzeFFoZF4jhws0abvht-                                                                                                                                     WIz44n1KZ5ERQDQ8AykGLgTHOTQsc9zhzb8zK4pdIgK0oJ0bYuUgLnhry9g4PGIMs70vvskX4vdGgYvt5cZCHKvXBQTGvarCHeJGFrfRj89FJAikQ5dXfHJg8sedBOBpJEYZ4X9PZD1URqhg0zYQs0YpPnmZbJ4v5OnOpPJGvFE31CBTHjkq6-NP3k6cOi7qCCAVbukq0cGnJTBOW32N8VBtGrig`
)
