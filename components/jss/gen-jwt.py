#!/usr/bin/python

# Copyright 2018 Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Python script generates a JWT signed witha private key and appends
chain of trust (x5c) to the header.
- issuer(iss) is passed as env. var. (ISS)
- token expiration is passed as env. var (TTL_SEC)

Example:
./gen-jwt.py --aud foo,bar --claimms name:tt|cluster-name:EUcluster|cluster-region:eu-de|images:trustedseriviceidentity/myubuntu@sha256:5b224e11f0,ubuntu:latest private-key.pem
"""
import argparse
import time
import os
from os.path import join, exists

from cryptography import x509
from cryptography.hazmat.backends import default_backend

from jwcrypto import jwt, jwk

# obtaind evn. variables:
expire = int(os.getenv('TTL_SEC', 30))
iss = os.getenv('ISS', 'wsched@us.ibm.com')
statedir = os.getenv('STATEDIR', '/host/tsi-secure')

def format_pem_cert(c):
    body = ""
    for i in xrange(0, len(c), 64):
        body += c[i:i+64] + '\n'

    return "-----BEGIN CERTIFICATE-----\n{}-----END CERTIFICATE-----".format(body)

def get_cert_claims(x5c):
    certClaims = {}
    for certData in x5c:
        cert = x509.load_pem_x509_certificate(format_pem_cert(certData), default_backend())
        for ex in cert.extensions:
            for uri in ex.value:
                f = str(uri.value)
                if f.startswith("TSI:") or f.startswith("tsi:"):
                    try:
                        sps = f[len("TSI:"):].split(":")
                        certClaims[sps[0]] =  ':'.join(sps[1:])
                    except:
                        raise Exception("Invalid TSI URI in x509 alt names")
        return certClaims

def check_payload (payload, certClaims):
    for k, v in certClaims.items():
        if k in payload and payload[k] != v:
            return None
        else:
            payload[k]=v

    return payload




def main(args):
    """Generates a signed JSON Web Token from local private key."""

    if os.path.isfile(args.key):
        with open(args.key) as f:
            pem_data = f.read()

        key = jwk.JWK.from_pem(pem_data)
    else:
        raise Exception('Unhandled key type: %s' % args.key)

    now = int(time.time())
    payload = {
        # expire in one hour.
        "exp": now + expire,
        "iat": now,
    }
    payload["iss"] = iss

    if args.sub:
        payload["sub"] = args.sub
    else:
        payload["sub"] = iss

    if args.aud:
        if "," in args.aud:
            payload["aud"] = args.aud.split(",")
        else:
            payload["aud"] = args.aud

    if args.claims:
        # we are using "|" to separate claims,
        # because `images` contain "," to seperate values
        # strip last `|` if any to remove empty claims
        for item in args.claims.rstrip('|').split("|"):
            # strip out all the doublequotes
            item = item.replace('"','')
            s = item.split(':')
            k = s[0]
            v = ':'.join(s[1:])
            payload[k] = v

    # add chain of trust
    x5cfile = join(statedir, "x5c")
    errMsg = "Error opening/processing x5c file"
    if exists(x5cfile):
        try:
            with open(x5cfile) as x:
                # serialize the given x5c as json Sring[]
                x5c = x.read().strip()[1:-1].replace('"', '').split(',')
                cc = get_cert_claims(x5c)
                payload = check_payload(payload, cc)
                if payload is None:
                    errMsg = "Payload claims do not match chain of trust"
                    raise Exception(errMsg)
                token = jwt.JWT(header={"alg": "RS256", "x5c":x5c, "typ": "JWT", "kid": key.key_id},
                    claims=payload)
                token.make_signed_token(key)
                return token.serialize()
        except Exception as e:
            # using without x5c chain of trust should be disabled
            print e
            raise e

    raise Exception("System not initialized. Missing x5c file. Abort!")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    # positional arguments
    parser.add_argument(
        'key',
        help='The path to the key pem file. The key can be generated with openssl command: `openssl genrsa -out key.pem 2048`')
    # optional arguments
    parser.add_argument("-aud", "--aud",
                        help="aud(audience) claim. This is comma-separated-list of audiences")
    parser.add_argument("-sub", "--sub",
                        help="sub(subject) claim. If not provided, it is set to the same as iss claim.")
    parser.add_argument("-claims", "--claims",
                         help="Other claims in format name1:value1|name2:value2 etc. Only string values are supported. Use `|` to seperate each claim")
    print main(parser.parse_args())
