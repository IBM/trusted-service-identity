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

"""Python script generates a JWT signed with custom private key.
issuer(iss) is passed as env. var. (ISS)
token expiration is passed as env. var (TTL_SEC)

Example:
./gen-jwt.py  --aud foo,bar --claims=email:foo@google.com|images:img1,img2 key.pem
"""
import argparse
import time
import os

from jwcrypto import jwt, jwk

expire = int(os.getenv('TTL_SEC', 30))
iss = os.getenv('ISS', 'wsched@us.ibm.com')

def main(args):
    """Generates a signed JSON Web Token from local private key."""

    # Begin modification
    if os.path.isfile(args.key):
        with open(args.key) as f:
            pem_data = f.read()
        f.closed

        key = jwk.JWK.from_pem(pem_data)
    else:
        key = jwk.JWK.from_uri(args.key)
    # End modification

    if args.jwks:
        with open(args.jwks, "w+") as fout:
            # this is the old JWKS format
            # fout.write("{ \"keys\":[ ")
            # fout.write(key.export(private_key=False))
            # fout.write("]}")

            # this is the new PEM format
            fout.write('{ "jwt_validation_pubkeys": "')
            fout.write(key.public().export_to_pem())
            fout.write('" }')
        fout.close

    now = int(time.time())
    payload = {
        # expire in one hour.
        "exp": now + expire,
        "iat": now,
    }
    payload["iss"] = iss
    payload["sub"] = iss
    # if args.iss:
    #     payload["iss"] = args.iss
    # if args.sub:
    #     payload["sub"] = args.sub
    # else:
    #     payload["sub"] = args.iss

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
    token = jwt.JWT(header={"alg": "RS256", "typ": "JWT", "kid": key.key_id},
                claims=payload)

    token.make_signed_token(key)

    return token.serialize()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    # positional arguments
    parser.add_argument(
        'key',
        help='The path to the key pem file. The key can be generated with openssl command: `openssl genrsa -out key.pem 2048`')
    # optional arguments
    parser.add_argument("-iss", "--iss",
                        default="testing@secure.istio.io",
                        help="iss claim. Default is `testing@secure.istio.io`")
    parser.add_argument("-aud", "--aud",
                        help="aud claim. This is comma-separated-list of audiences")
    parser.add_argument("-sub", "--sub",
                        help="sub claim. If not provided, it is set to the same as iss claim.")
    parser.add_argument("-claims", "--claims",
                         help="Other claims in format name1:value1|name2:value2 etc. Only string values are supported. Use `|` to seperate each claim")
    parser.add_argument("-jwks", "--jwks",
                         help="Path to the output file for JWKS.")
    parser.add_argument("-expire", "--expire", type=int, default=3600,
                         help="JWT expiration time in second. Default is 1 hour.")
    print main(parser.parse_args())
