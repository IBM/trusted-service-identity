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

// See folder "./gen-test-cred-helpers" for information on how to generate
// these test credentials
const (
	// CACert.pem
	pubCA string = `-----BEGIN CERTIFICATE-----
MIICljCCAX4CCQD7gfotoz2lszANBgkqhkiG9w0BAQsFADANMQswCQYDVQQGEwJV
UzAeFw0yMTA3MjExODM4MDBaFw0zMTA3MTkxODM4MDBaMA0xCzAJBgNVBAYTAlVT
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwKl7Y2Zkugeq1KuC9n4V
VaY3peeMs8qT3ZgI06K+Ltz2k63wzcr1wx2Nc3k/BEmaD9TJZ0eetxYvifbpQ5Tr
KVf+wF0aAXFwVORtyi4UOzvT9bLOyzFMhAa+C4gVi2TvAVn6YSKe7nBlOY54g28N
jvqxNpfAuzbxXzlQpJLrUrQ3fXDf3lA54xaAXbmV9g7rpKdnF7NjMpj4qjTRm+eX
AX/M5vLAmxs/6HL6YXb/2T9G7Ti/fmEnQL21oeluDG2bMWaogmlSzeS4cFA1LJwh
bqIRBhv9vQcGQtR79pO1KfRK7dwn8SvarL7qqivlQhWz/AnITMnxOyOao4gDQxSF
vQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAyQgAT21/NZebynRoFeYsEIxLeZi6g
JcgPLNKULcoGQ8bQmQpAjXFc6tHBkIy/oJXu3q/fbAtLycr1zbeP66Y3avP72Stn
o1+CCsn8TUmcnpIM+g1OOit4T+Ag6cUwF4OqWEcpQKS3ypCrvWTrIdZe3242VuH2
z+PmsIB6dYv9/YYZJPDvKY7wiFXrsbs1/2ouxf+wK/STaE0rxIsDLWJh93ocC8vN
+VUodT3G6JSwuMH4EA75FwCIXDcn5FF+FD4oXQxWsON/Er+cp8yk8VFVjhVeXiJC
uldru76mvHljzEv3nMInMywNFECQBDHIP79yoNz6jJLTnws900+eaBy9
-----END CERTIFICATE-----`

	// CA.key
	privCA string = `-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAwKl7Y2Zkugeq1KuC9n4VVaY3peeMs8qT3ZgI06K+Ltz2k63w
zcr1wx2Nc3k/BEmaD9TJZ0eetxYvifbpQ5TrKVf+wF0aAXFwVORtyi4UOzvT9bLO
yzFMhAa+C4gVi2TvAVn6YSKe7nBlOY54g28NjvqxNpfAuzbxXzlQpJLrUrQ3fXDf
3lA54xaAXbmV9g7rpKdnF7NjMpj4qjTRm+eXAX/M5vLAmxs/6HL6YXb/2T9G7Ti/
fmEnQL21oeluDG2bMWaogmlSzeS4cFA1LJwhbqIRBhv9vQcGQtR79pO1KfRK7dwn
8SvarL7qqivlQhWz/AnITMnxOyOao4gDQxSFvQIDAQABAoIBADywJnH1Ox1udN1w
+Vvz83x7U2QrQCMSWOmgjoc76HSSngl+7S+mEyxXDsulEbikBqed+6NQ6Cn8DxWC
dZAYRMtNMK4fpaV2uk/DdOIPCchu3CG1JXbUHKoqBYtUXpT+QltGoJwgb7fkJ76t
pkCgpsC3L0NnIgrXD8lTIJf2v7HZDojS5Z4qJexkVGxWQNbH9WnYzke0pnK5cruU
Ic53yB2z2+TzdYsnx/Ldvinu19KW18zcgizBTpKiUV6WVBiDzA2JlkB1QCKYjpsR
bK5eILPzAQUvpEfJTFMpEcjqROepB51oLQiZnt4G4ZNgKBdAAeLQ/8P8jfuM7YHR
Wviq4YECgYEA8ZNelUbSk3wYZfqqFzcZiJzdlIZq0CHPXGMuVwcOuE8VbRWn2Mf6
6m6E4LSHUY9BziLURGu0iBUM3gU+OPvKf1Y41xJPyjavWfAeSzi4/dimVcPudHu2
KXw4LSjSIQw/xqddCedOlU/zANhDdTyJ8SduyPIcQG48QVZ17Fz4aFkCgYEAzCpw
KL/e0h7XmehPXnESgFLCoOils6mQv2IsD4GhlJJsCn2e5tmO6NzqkNNQ+s7xMLiu
M9PiM3vWfZ8Nr2ZaItVnm6SioNkr7gGbuEDWAXul22YVA6HfeBOTqkvYhahe3JZ1
dtFiKdZZ7lr9FDbZkuER0FGMLy/f8eURVes+3AUCgYB1XYO2QpJL1R6FbSL15G8j
UBLW9fcu5z43RHhfD663HLTsKnlBeOcOvmMQSKT1mwP9gi5ej3VGJ/P4adOxG6Nl
+h3jX6IkPC01JNOS+BvoODmXsXlIXlJCFXe1eP+dzrWtbeJlzVsAb7c/0dH0Q1VB
NEc+mWHga64akEb6brDBAQKBgB+fhyXYqkOzgUOWhwyiyPHVX84amufcIM5z/00b
kBJ6J3/seztYgVkyNqbeBFIE0bjxMhJXBFdjHBLzGuSLHvT8RwMFmib93F8OIreE
W2F5bHQyOJkKbpmjtqCPBOeW77KNH36a6fB/Agj4UPDbmhG1CNRSfTsl2DMYfvnm
6SKdAoGBAKlfFRpqUTN+DZn/ImhnEuSOCk67MFZ1pRHEKbuau0gtBtVmdSZUnt+r
ChTozb2NgTwKsWH0XtumYHOPZ/5YzXr69EiOuI5fc/AtJDrRHXv0ePR0O7oPOm3o
BBPoCAy42jK2JWBhre+sUPZz0uATIhdFIeMstjIn6HT5l9Bc1Tz2
-----END RSA PRIVATE KEY-----`

	// Arbitrary private key
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

	// intermediateCA.pem
	testTokenCert string = `-----BEGIN CERTIFICATE-----
MIIC4zCCAcugAwIBAgIJAKl2fBQFO7gDMA0GCSqGSIb3DQEBBQUAMA0xCzAJBgNV
BAYTAlVTMB4XDTIxMDcyMjE5NDg0OVoXDTMxMDcyMDE5NDg0OVowGTEXMBUGA1UE
AwwOaW50ZXJtZWRpYXRlQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
AQDBxqslK+RJ8D+xeUcgzCpbzi+0SQDAy6oFVK9LIcoK4q5NCjWayWdQA3VtuUbU
y5TvGXj3ZuGEtp/EDAjzoTI4cHD3WksdNlG7fp+6sG7nFgYT1afQZtllpceCYZgb
38d1loup6sUa7vMmwzhRqt/gvwdqWszx8sLzeDccSPIygkEIa8L2eVWnh5mxzmJq
mKZAS0QVwSPDaIO4Y0sq837Hye2cRtVLGuArSidTfx1uPT6kIFL71bKqFdcSnTvx
I6dZ1NBOj6XgyiQt78yQjo8IQaOU3cPakpmaL4nxedLLJ2ODUC23YK6Xq5ETr+Nr
+Rk0d8kBMYngxIh49rCi7akjAgMBAAGjOjA4MDYGA1UdEQQvMC2GEFRTSTpyZWdp
b246ZXUtZGWGGVRTSTpjbHVzdGVyLW5hbWU6dGktdGVzdDEwDQYJKoZIhvcNAQEF
BQADggEBAFkscu392AdhJiHW8dhBajczLuAxPuk0QyqBZ5TPLBQiLF1ExPCqV0Rs
hpxGqkhyUvZjC9FqdXDAb68jUa2sqMe8IVRXpQ7rW49fxkh/7V40s8lDKdec1ajS
9w9+A4S90arpv5j9aH7YlE2k1mQxUoGZuRWl6XrFVVlOI3Z/GYrAOCNbAgFOsfZD
ckzoNk+c8utJfPO/jw9RNDfFH0jAGZlEe0XGhABEhhAkagolFIxmAEdy9CCb9DyK
e/yGprdWuD8RH/LBcS9hQPe0QkruGwFhYSsEn/zS4ddBZOCMk2URvCg+y3oeByqg
nTDk9zNckthiV0octGdZxm0USsg5H44=
-----END CERTIFICATE-----`

	testGoodToken string = `eyJhbGciOiJSUzI1NiIsImtpZCI6IjRTdzR3MC1LVGNGNU9mVE10MmR4X3ZjVk1UQmtCLVJTbGFBUWkyNTdEX3MiLCJ0eXAiOiJKV1QiLCJ4NWMiOlsiTUlJQzR6Q0NBY3VnQXdJQkFnSUpBS2wyZkJRRk83Z0RNQTBHQ1NxR1NJYjNEUUVCQlFVQU1BMHhDekFKQmdOVkJBWVRBbFZUTUI0WERUSXhNRGN5TWpFNU5EZzBPVm9YRFRNeE1EY3lNREU1TkRnME9Wb3dHVEVYTUJVR0ExVUVBd3dPYVc1MFpYSnRaV1JwWVhSbFEwRXdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFEQnhxc2xLK1JKOEQreGVVY2d6Q3BiemkrMFNRREF5Nm9GVks5TEljb0s0cTVOQ2pXYXlXZFFBM1Z0dVViVXk1VHZHWGozWnVHRXRwL0VEQWp6b1RJNGNIRDNXa3NkTmxHN2ZwKzZzRzduRmdZVDFhZlFadGxscGNlQ1laZ2IzOGQxbG91cDZzVWE3dk1td3poUnF0L2d2d2RxV3N6eDhzTHplRGNjU1BJeWdrRUlhOEwyZVZXbmg1bXh6bUpxbUtaQVMwUVZ3U1BEYUlPNFkwc3E4MzdIeWUyY1J0VkxHdUFyU2lkVGZ4MXVQVDZrSUZMNzFiS3FGZGNTblR2eEk2ZFoxTkJPajZYZ3lpUXQ3OHlRam84SVFhT1UzY1Bha3BtYUw0bnhlZExMSjJPRFVDMjNZSzZYcTVFVHIrTnIrUmswZDhrQk1Zbmd4SWg0OXJDaTdha2pBZ01CQUFHak9qQTRNRFlHQTFVZEVRUXZNQzJHRUZSVFNUcHlaV2RwYjI0NlpYVXRaR1dHR1ZSVFNUcGpiSFZ6ZEdWeUxXNWhiV1U2ZEdrdGRHVnpkREV3RFFZSktvWklodmNOQVFFRkJRQURnZ0VCQUZrc2N1MzkyQWRoSmlIVzhkaEJhamN6THVBeFB1azBReXFCWjVUUExCUWlMRjFFeFBDcVYwUnNocHhHcWtoeVV2WmpDOUZxZFhEQWI2OGpVYTJzcU1lOElWUlhwUTdyVzQ5ZnhraC83VjQwczhsREtkZWMxYWpTOXc5K0E0UzkwYXJwdjVqOWFIN1lsRTJrMW1ReFVvR1p1UldsNlhyRlZWbE9JM1ovR1lyQU9DTmJBZ0ZPc2ZaRGNrem9OaytjOHV0SmZQTy9qdzlSTkRmRkgwakFHWmxFZTBYR2hBQkVoaEFrYWdvbEZJeG1BRWR5OUNDYjlEeUtlL3lHcHJkV3VEOFJIL0xCY1M5aFFQZTBRa3J1R3dGaFlTc0VuL3pTNGRkQlpPQ01rMlVSdkNnK3kzb2VCeXFnblREazl6TmNrdGhpVjBvY3RHZFp4bTBVU3NnNUg0ND0iLCJNSUlDbGpDQ0FYNENDUUQ3Z2ZvdG96MmxzekFOQmdrcWhraUc5dzBCQVFzRkFEQU5NUXN3Q1FZRFZRUUdFd0pWVXpBZUZ3MHlNVEEzTWpFeE9ETTRNREJhRncwek1UQTNNVGt4T0RNNE1EQmFNQTB4Q3pBSkJnTlZCQVlUQWxWVE1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBd0tsN1kyWmt1Z2VxMUt1QzluNFZWYVkzcGVlTXM4cVQzWmdJMDZLK0x0ejJrNjN3emNyMXd4Mk5jM2svQkVtYUQ5VEpaMGVldHhZdmlmYnBRNVRyS1ZmK3dGMGFBWEZ3Vk9SdHlpNFVPenZUOWJMT3l6Rk1oQWErQzRnVmkyVHZBVm42WVNLZTduQmxPWTU0ZzI4Tmp2cXhOcGZBdXpieFh6bFFwSkxyVXJRM2ZYRGYzbEE1NHhhQVhibVY5ZzdycEtkbkY3TmpNcGo0cWpUUm0rZVhBWC9NNXZMQW14cy82SEw2WVhiLzJUOUc3VGkvZm1FblFMMjFvZWx1REcyYk1XYW9nbWxTemVTNGNGQTFMSndoYnFJUkJodjl2UWNHUXRSNzlwTzFLZlJLN2R3bjhTdmFyTDdxcWl2bFFoV3ovQW5JVE1ueE95T2FvNGdEUXhTRnZRSURBUUFCTUEwR0NTcUdTSWIzRFFFQkN3VUFBNElCQVFBeVFnQVQyMS9OWmVieW5Sb0ZlWXNFSXhMZVppNmdKY2dQTE5LVUxjb0dROGJRbVFwQWpYRmM2dEhCa0l5L29KWHUzcS9mYkF0THljcjF6YmVQNjZZM2F2UDcyU3RubzErQ0NzbjhUVW1jbnBJTStnMU9PaXQ0VCtBZzZjVXdGNE9xV0VjcFFLUzN5cENydldUcklkWmUzMjQyVnVIMnorUG1zSUI2ZFl2OS9ZWVpKUER2S1k3d2lGWHJzYnMxLzJvdXhmK3dLL1NUYUUwcnhJc0RMV0poOTNvY0M4dk4rVlVvZFQzRzZKU3d1TUg0RUE3NUZ3Q0lYRGNuNUZGK0ZENG9YUXhXc09OL0VyK2NwOHlrOFZGVmpoVmVYaUpDdWxkcnU3Nm12SGxqekV2M25NSW5NeXdORkVDUUJESElQNzl5b056NmpKTFRud3M5MDArZWFCeTkiXX0.eyJhdWQiOiJ0ZXN0IiwiZXhwIjoxNjI2OTg0MTAwLCJpYXQiOjE2MjY5ODQwNzAsImlzcyI6IndzY2hlZEB1cy5pYm0uY29tIiwicmVnaW9uIjoiZXUtZGUiLCJzb21lIjoiY2xhaW0iLCJzdWIiOiJ0ZXN0In0.XZFeeLeqoNRvgXNUV57dc9LcyDdbdhwu360eow1DjNkJjyv6Tdz40wnV9SowrhD_bWVJb64w0Ki6asmXeYnZ3nNb2kjlPFGIpZkyQBARrd8Os_xf58zUaCRIyvLWvXD126GdyhmebPwZ_2ZLqFNfxmaXuFed4326wKY4kn5mbxktxdaaGT_PDQWGZ37M0Tqpv8susYmqGTrAgA9exgAMBAQT7eDPYrJ4O1tVjktMqVUwRSkgld2NpBofnj7w01iZzSgoWPEUKO2oMocPpv8BFMriaInWKCUawUTtmuwgEJnaxDy7aN-fgnchQMo-vYGOnSijlw1w7AfOx0ZWcl09rA`

	testBadToken string = `eyJhbGciOiJSUzI1NiIsImtpZCI6IjRTdzR3MC1LVGNGNU9mVE10MmR4X3ZjVk1UQmtCLVJTbGFBUWkyNTdEX3MiLCJ0eXAiOiJKV1QiLCJ4NWMiOlsiTUlJQzR6Q0NBY3VnQXdJQkFnSUpBS2wyZkJRRk83Z0RNQTBHQ1NxR1NJYjNEUUVCQlFVQU1BMHhDekFKQmdOVkJBWVRBbFZUTUI0WERUSXhNRGN5TWpFNU5EZzBPVm9YRFRNeE1EY3lNREU1TkRnME9Wb3dHVEVYTUJVR0ExVUVBd3dPYVc1MFpYSnRaV1JwWVhSbFEwRXdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFEQnhxc2xLK1JKOEQreGVVY2d6Q3BiemkrMFNRREF5Nm9GVks5TEljb0s0cTVOQ2pXYXlXZFFBM1Z0dVViVXk1VHZHWGozWnVHRXRwL0VEQWp6b1RJNGNIRDNXa3NkTmxHN2ZwKzZzRzduRmdZVDFhZlFadGxscGNlQ1laZ2IzOGQxbG91cDZzVWE3dk1td3poUnF0L2d2d2RxV3N6eDhzTHplRGNjU1BJeWdrRUlhOEwyZVZXbmg1bXh6bUpxbUtaQVMwUVZ3U1BEYUlPNFkwc3E4MzdIeWUyY1J0VkxHdUFyU2lkVGZ4MXVQVDZrSUZMNzFiS3FGZGNTblR2eEk2ZFoxTkJPajZYZ3lpUXQ3OHlRam84SVFhT1UzY1Bha3BtYUw0bnhlZExMSjJPRFVDMjNZSzZYcTVFVHIrTnIrUmswZDhrQk1Zbmd4SWg0OXJDaTdha2pBZ01CQUFHak9qQTRNRFlHQTFVZEVRUXZNQzJHRUZSVFNUcHlaV2RwYjI0NlpYVXRaR1dHR1ZSVFNUcGpiSFZ6ZEdWeUxXNWhiV1U2ZEdrdGRHVnpkREV3RFFZSktvWklodmNOQVFFRkJRQURnZ0VCQUZrc2N1MzkyQWRoSmlIVzhkaEJhamN6THVBeFB1azBReXFCWjVUUExCUWlMRjFFeFBDcVYwUnNocHhHcWtoeVV2WmpDOUZxZFhEQWI2OGpVYTJzcU1lOElWUlhwUTdyVzQ5ZnhraC83VjQwczhsREtkZWMxYWpTOXc5K0E0UzkwYXJwdjVqOWFIN1lsRTJrMW1ReFVvR1p1UldsNlhyRlZWbE9JM1ovR1lyQU9DTmJBZ0ZPc2ZaRGNrem9OaytjOHV0SmZQTy9qdzlSTkRmRkgwakFHWmxFZTBYR2hBQkVoaEFrYWdvbEZJeG1BRWR5OUNDYjlEeUtlL3lHcHJkV3VEOFJIL0xCY1M5aFFQZTBRa3J1R3dGaFlTc0VuL3pTNGRkQlpPQ01rMlVSdkNnK3kzb2VCeXFnblREazl6TmNrdGhpVjBvY3RHZFp4bTBVU3NnNUg0ND0iLCJNSUlDbGpDQ0FYNENDUUQ3Z2ZvdG96MmxzekFOQmdrcWhraUc5dzBCQVFzRkFEQU5NUXN3Q1FZRFZRUUdFd0pWVXpBZUZ3MHlNVEEzTWpFeE9ETTRNREJhRncwek1UQTNNVGt4T0RNNE1EQmFNQTB4Q3pBSkJnTlZCQVlUQWxWVE1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBd0tsN1kyWmt1Z2VxMUt1QzluNFZWYVkzcGVlTXM4cVQzWmdJMDZLK0x0ejJrNjN3emNyMXd4Mk5jM2svQkVtYUQ5VEpaMGVldHhZdmlmYnBRNVRyS1ZmK3dGMGFBWEZ3Vk9SdHlpNFVPenZUOWJMT3l6Rk1oQWErQzRnVmkyVHZBVm42WVNLZTduQmxPWTU0ZzI4Tmp2cXhOcGZBdXpieFh6bFFwSkxyVXJRM2ZYRGYzbEE1NHhhQVhibVY5ZzdycEtkbkY3TmpNcGo0cWpUUm0rZVhBWC9NNXZMQW14cy82SEw2WVhiLzJUOUc3VGkvZm1FblFMMjFvZWx1REcyYk1XYW9nbWxTemVTNGNGQTFMSndoYnFJUkJodjl2UWNHUXRSNzlwTzFLZlJLN2R3bjhTdmFyTDdxcWl2bFFoV3ovQW5JVE1ueE95T2FvNGdEUXhTRnZRSURBUUFCTUEwR0NTcUdTSWIzRFFFQkN3VUFBNElCQVFBeVFnQVQyMS9OWmVieW5Sb0ZlWXNFSXhMZVppNmdKY2dQTE5LVUxjb0dROGJRbVFwQWpYRmM2dEhCa0l5L29KWHUzcS9mYkF0THljcjF6YmVQNjZZM2F2UDcyU3RubzErQ0NzbjhUVW1jbnBJTStnMU9PaXQ0VCtBZzZjVXdGNE9xV0VjcFFLUzN5cENydldUcklkWmUzMjQyVnVIMnorUG1zSUI2ZFl2OS9ZWVpKUER2S1k3d2lGWHJzYnMxLzJvdXhmK3dLL1NUYUUwcnhJc0RMV0poOTNvY0M4dk4rVlVvZFQzRzZKU3d1TUg0RUE3NUZ3Q0lYRGNuNUZGK0ZENG9YUXhXc09OL0VyK2NwOHlrOFZGVmpoVmVYaUpDdWxkcnU3Nm12SGxqekV2M25NSW5NeXdORkVDUUJESElQNzl5b056NmpKTFRud3M5MDArZWFCeTkiXX0.eyJhdWQiOiJ0ZXN0IiwiZXhwIjoxNjI2OTgzODY3LCJpYXQiOjE2MjY5ODM4MzcsImlzcyI6IndzY2hlZEB1cy5pYm0uY29tIiwicmVnaW9uIjoidXMiLCJzb21lIjoiY2xhaW0iLCJzdWIiOiJ0ZXN0In0.Dtrxovr6fvKv04ef-kOz45fLuGyRlaBfCaSWR2Dxig6Q5mBbUbR4UlXAKz2xefDqMwITGvJ6I9JkPOuXAWFrttU-W-e_kYJxlZrq-PcOXMlJxmufySbHIL9AmaoQqRE_Ho0wO0W6MmiUKAPOelf7XI0TyEIaA0ey6_tRtX4DcNxXjmvopkZtZP1dg7lETOt7KVTKyNf13mD5U6_3BCHr8g5lUuywR4Wj1B48Q9q0UXzMVTz7SNO_LTESntXQNmVj1KjPjN5kTzRmi-kYpH6YMvBnpy4mOq-5GLXtMWVy9wSu7_S1gViTIw0TCzKb5eLUTd1YXWVqpyMvuvoZXDo40w`
)
