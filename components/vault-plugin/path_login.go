package jwtauth

import (
	"context"
	"crypto/x509"
	"fmt"
	"strings"
	"time"

	"github.com/pkg/errors"

	oidc "github.com/coreos/go-oidc"
	"github.com/hashicorp/errwrap"
	"github.com/hashicorp/vault/helper/cidrutil"
	"github.com/hashicorp/vault/helper/strutil"
	"github.com/hashicorp/vault/logical"
	"github.com/hashicorp/vault/logical/framework"
	"gopkg.in/square/go-jose.v2/jwt"
)

func pathLogin(b *jwtAuthBackend) *framework.Path {
	return &framework.Path{
		Pattern: `login$`,
		Fields: map[string]*framework.FieldSchema{
			"role": {
				Type:        framework.TypeLowerCaseString,
				Description: "The role to log in against.",
			},
			"jwt": {
				Type:        framework.TypeString,
				Description: "The signed JWT to validate.",
			},
		},

		Callbacks: map[logical.Operation]framework.OperationFunc{
			logical.UpdateOperation:         b.pathLogin,
			logical.AliasLookaheadOperation: b.pathLogin,
		},

		HelpSynopsis:    pathLoginHelpSyn,
		HelpDescription: pathLoginHelpDesc,
	}
}

// getCertChainClaimsMap obtains the TSI claims which are part of the CA
// chain used to verify a JWT. This implies that the claims from the claim
// must meet the requirements put forth by the chain of trust.
func getCertChainClaimsMap(certs []*x509.Certificate) (map[string]string, error) {
	// It is important to go through every cert and overwrite the map claims
	// to prevent an attack where an intermediate CA can be used to sign another
	// set of CAs which do not have these extended names. So each attribute
	// must be propagated down which can be done by traversing and populating
	// the map in reverse order.
	claimsMap := map[string]string{}
	for _, cert := range certs {
		for _, v := range cert.URIs {
			if strings.ToUpper(v.Scheme) == "TSI" {
				ss := strings.Split(v.Opaque, ":")
				if len(ss) < 2 {
					return nil, errors.New("TSI alt name is not in correct format")
				}
				k := ss[0]
				v := strings.Join(ss[1:], ":")
				claimsMap[k] = v
			}
		}
	}

	return claimsMap, nil
}

// validateCertChain validates the jwt cert chain and returns the public key
// that can validate the JWT if verifiable
func validateCertChain(rootCAPEM []byte, jwtToken *jwt.JSONWebToken) (interface{}, map[string]string, error) {
	roots := x509.NewCertPool()
	ok := roots.AppendCertsFromPEM(rootCAPEM)
	if !ok {
		return nil, nil, fmt.Errorf("Error appending root cert in x509 CertPool")
	}

	opts := x509.VerifyOptions{
		Roots:         roots,
		Intermediates: nil,
	}

	for _, h := range jwtToken.Headers {
		certs, err := h.Certificates(opts)
		if err == nil && len(certs) > 0 && len(certs[0]) > 0 {
			claims, err := getCertChainClaimsMap(certs[0])
			if err != nil {
				return nil, nil, err
			}

			fmt.Printf("Verification Success! %v\n", certs)
			return certs[0][0].PublicKey, claims, nil
		}
	}

	return nil, nil, fmt.Errorf("Unable to verify cert chain")
}

func checkClaims(certClaims map[string]string, payload map[string]interface{}) error {
	for k, v := range certClaims {
		if vv, ok := payload[k]; ok {
			if vvString, _ := vv.(string); vvString != v {
				return errors.Errorf("Trust chain assertion of field %v failed, expected %v, got %v",
					k, v, vvString)

			}
		}
	}
	return nil
}

func (b *jwtAuthBackend) pathLogin(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	token := d.Get("jwt").(string)
	if len(token) == 0 {
		return logical.ErrorResponse("missing token"), nil
	}

	roleName := d.Get("role").(string)
	if len(roleName) == 0 {
		return logical.ErrorResponse("missing role"), nil
	}

	role, err := b.role(ctx, req.Storage, roleName)
	if err != nil {
		return nil, err
	}
	if role == nil {
		return logical.ErrorResponse("role could not be found"), nil
	}

	if req.Connection != nil && !cidrutil.RemoteAddrIsOk(req.Connection.RemoteAddr, role.BoundCIDRs) {
		return logical.ErrorResponse("request originated from invalid CIDR"), nil
	}

	config, err := b.config(ctx, req.Storage)
	if err != nil {
		return nil, err
	}
	if config == nil {
		return logical.ErrorResponse("could not load configuration"), nil
	}

	// Here is where things diverge. If it is using OIDC Discovery, validate
	// that way; otherwise validate against the locally configured keys. Once
	// things are validated, we re-unify the request path when evaluating the
	// claims.
	allClaims := map[string]interface{}{}
	switch {
	case len(config.ParsedJWTPubKeys) != 0:
		parsedJWT, err := jwt.ParseSigned(token)
		if err != nil {
			return logical.ErrorResponse(errwrap.Wrapf("error parsing token: {{err}}", err).Error()), nil
		}

		claims := jwt.Claims{}
		var valid bool
		errMsg := ""
		for i, key := range config.JWTValidationPubKeys {
			var validateKey interface{}
			// If there is a valid x5c chain, do chain validation and use the
			// provided CA (first cert of chain as the public key) which acts
			// as the intermediary.
			validateKey, certClaims, err := validateCertChain([]byte(key), parsedJWT)
			if err != nil {
				// If can't validate cert chain, use the rootCA public key
				fmt.Printf("Couldn't validate cert chain\n")
				validateKey = config.ParsedJWTPubKeys[i]
			}

			if err := parsedJWT.Claims(validateKey, &claims, &allClaims); err == nil {
				if err = checkClaims(certClaims, allClaims); err != nil {
					errMsg = err.Error()
					continue
				}
				valid = true
				break
			}
		}
		if !valid {
			if errMsg == "" {
				errMsg = "no known key successfully validated the token signature"
			}
			return logical.ErrorResponse(errMsg), nil
		}

		// We require notbefore or expiry; if only one is provided, we allow 5 minutes of leeway.
		if claims.IssuedAt == jwt.NumericDate(0) && claims.Expiry == jwt.NumericDate(0) && claims.NotBefore == jwt.NumericDate(0) {
			return logical.ErrorResponse("no issue time, notbefore, or expiration time encoded in token"), nil
		}
		if claims.Expiry == 0 {
			latestStart := claims.IssuedAt
			if claims.NotBefore > claims.IssuedAt {
				latestStart = claims.NotBefore
			}
			claims.Expiry = latestStart + 300
		}
		if claims.NotBefore == 0 {
			if claims.IssuedAt != 0 {
				claims.NotBefore = claims.IssuedAt
			} else {
				claims.NotBefore = claims.Expiry - 300
			}
		}

		if len(claims.Audience) > 0 && len(role.BoundAudiences) == 0 {
			return logical.ErrorResponse("audience claim found in JWT but no audiences bound to the role"), nil
		}

		expected := jwt.Expected{
			Issuer:   config.BoundIssuer,
			Subject:  role.BoundSubject,
			Audience: jwt.Audience(role.BoundAudiences),
			Time:     time.Now(),
		}

		if err := claims.Validate(expected); err != nil {
			return logical.ErrorResponse(errwrap.Wrapf("error validating claims: {{err}}", err).Error()), nil
		}

	case config.OIDCDiscoveryURL != "":
		provider, err := b.getProvider(ctx, config)
		if err != nil {
			return nil, errwrap.Wrapf("error getting provider for login operation: {{err}}", err)
		}

		verifier := provider.Verifier(&oidc.Config{
			SkipClientIDCheck: true,
		})

		idToken, err := verifier.Verify(ctx, token)
		if err != nil {
			return logical.ErrorResponse(errwrap.Wrapf("error validating signature: {{err}}", err).Error()), nil
		}

		if err := idToken.Claims(&allClaims); err != nil {
			return logical.ErrorResponse(errwrap.Wrapf("unable to successfully parse all claims from token: {{err}}", err).Error()), nil
		}

		if role.BoundSubject != "" && role.BoundSubject != idToken.Subject {
			return logical.ErrorResponse("sub claim does not match bound subject"), nil
		}
		if len(role.BoundAudiences) != 0 {
			var found bool
			for _, v := range role.BoundAudiences {
				if strutil.StrListContains(idToken.Audience, v) {
					found = true
					break
				}
			}
			if !found {
				return logical.ErrorResponse("aud claim does not match any bound audience"), nil
			}
		}

	default:
		return nil, errors.New("unhandled case during login")
	}

	userClaimRaw, ok := allClaims[role.UserClaim]
	if !ok {
		return logical.ErrorResponse(fmt.Sprintf("%q claim not found in token", role.UserClaim)), nil
	}
	userName, ok := userClaimRaw.(string)
	if !ok {
		return logical.ErrorResponse(fmt.Sprintf("%q claim could not be converted to string", role.UserClaim)), nil
	}

	// add all configured claims as metadata
	metadata := map[string]string{}
	for _, claimName := range role.MetadataClaims {
		claimRaw, ok := allClaims[claimName]
		if !ok {
			return logical.ErrorResponse(fmt.Sprintf("%q claim not found in token", claimName)), nil
		}
		claimValue, ok := claimRaw.(string)
		if !ok {
			return logical.ErrorResponse(fmt.Sprintf("%q claim could not be converted to string", claimName)), nil
		}
		metadata[claimName] = claimValue
	}

	var groupAliases []*logical.Alias
	if role.GroupsClaim != "" {
		mapPath, err := parseClaimWithDelimiters(role.GroupsClaim, role.GroupsClaimDelimiterPattern)
		if err != nil {
			return logical.ErrorResponse(errwrap.Wrapf("error parsing delimiters for groups claim: {{err}}", err).Error()), nil
		}
		if len(mapPath) < 1 {
			return logical.ErrorResponse("unexpected length 0 of claims path after parsing groups claim against delimiters"), nil
		}
		var claimKey string
		claimMap := allClaims
		for i, key := range mapPath {
			if i == len(mapPath)-1 {
				claimKey = key
				break
			}
			nextMapRaw, ok := claimMap[key]
			if !ok {
				return logical.ErrorResponse(fmt.Sprintf("map via key %q not found while navigating group claim delimiters", key)), nil
			}
			nextMap, ok := nextMapRaw.(map[string]interface{})
			if !ok {
				return logical.ErrorResponse(fmt.Sprintf("key %q does not reference a map while navigating group claim delimiters", key)), nil
			}
			claimMap = nextMap
		}

		groupsClaimRaw, ok := claimMap[claimKey]
		if !ok {
			return logical.ErrorResponse(fmt.Sprintf("%q claim not found in token", role.GroupsClaim)), nil
		}
		groups, ok := groupsClaimRaw.([]interface{})
		if !ok {
			return logical.ErrorResponse(fmt.Sprintf("%q claim could not be converted to string list", role.GroupsClaim)), nil
		}
		for _, groupRaw := range groups {
			group, ok := groupRaw.(string)
			if !ok {
				return logical.ErrorResponse(fmt.Sprintf("value %v in groups claim could not be parsed as string", groupRaw)), nil
			}
			if group == "" {
				continue
			}
			groupAliases = append(groupAliases, &logical.Alias{
				Name: group,
			})
		}
	}

	// add the role name as metadata
	metadata["role"] = roleName

	resp := &logical.Response{
		Auth: &logical.Auth{
			Policies:    role.Policies,
			DisplayName: userName,
			Period:      role.Period,
			NumUses:     role.NumUses,
			Alias: &logical.Alias{
				Name:     userName,
				Metadata: metadata,
			},
			GroupAliases: groupAliases,
			InternalData: map[string]interface{}{
				"role": roleName,
			},
			Metadata: metadata,
			LeaseOptions: logical.LeaseOptions{
				Renewable: true,
				TTL:       role.TTL,
				MaxTTL:    role.MaxTTL,
			},
			BoundCIDRs: role.BoundCIDRs,
		},
	}

	return resp, nil
}

func (b *jwtAuthBackend) pathLoginRenew(ctx context.Context, req *logical.Request, data *framework.FieldData) (*logical.Response, error) {
	roleName := req.Auth.InternalData["role"].(string)
	if roleName == "" {
		return nil, errors.New("failed to fetch role_name during renewal")
	}

	// Ensure that the Role still exists.
	role, err := b.role(ctx, req.Storage, roleName)
	if err != nil {
		return nil, errwrap.Wrapf(fmt.Sprintf("failed to validate role %s during renewal: {{err}}", roleName), err)
	}
	if role == nil {
		return nil, fmt.Errorf("role %s does not exist during renewal", roleName)
	}

	resp := &logical.Response{Auth: req.Auth}
	resp.Auth.TTL = role.TTL
	resp.Auth.MaxTTL = role.MaxTTL
	resp.Auth.Period = role.Period
	return resp, nil
}

const (
	pathLoginHelpSyn = `
	Authenticates to Vault using a JWT (or OIDC) token.
	`
	pathLoginHelpDesc = `
Authenticates JWTs.
`
)
