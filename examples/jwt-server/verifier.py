import argparse
import json
import time
import policy
from StringIO import StringIO
from jwcrypto import jwt, jwk

class JWTVerifier:
    jwk_list = None

    def __init__(self, jwks=None):
        self.jwk_list = []
        # If provide a default jwks, provide loose claims policy
        if jwks:
            self.jwk_list. append((parseJWKFile(jwks), policy.ClaimsPolicy({})))

    # Register a jwks with a set of claims that the JWT needs to have.
    def register (self, jwks, claims):
        self.jwk_list.append((parseJWKFile(jwks), policy.ClaimsPolicy(claims)))

    def getClaims(self, token):
        for jwk, pol in self.jwk_list:
            try:
                st = jwt.JWT(key=jwk, jwt=token)
                claims = json.load(StringIO(st.claims))

                if pol.check(claims):
                    return claims
                else:
                    return None
            except:
                pass

        return None

# TODO: Handle multiple keys within 1 jwks
def parseJWKFile(jwks):
  kjson = json.load(StringIO(jwks))
  keys = kjson["keys"]
  key = jwk.JWK(**(keys[0]))
  return key
