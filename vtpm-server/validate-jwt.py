#!/usr/bin/env python

import argparse
import os

from jwcrypto import jwt, jwk

def main(args):
    if os.path.isfile(args.key):
        with open(args.key) as f:
            pem_data = f.read()
        f.closed

        key = jwk.JWK.from_pem(pem_data)
    else:
        key = jwk.JWK.from_uri(args.key)

    with open(args.jwt) as f:
        raw_jwt = f.read()
    f.closed
    token = jwt.JWT()
    token.deserialize(raw_jwt, key)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    # positional arguments
    parser.add_argument(
        'key',
        help='The path to the public key pem file.')
    parser.add_argument(
        'jwt',
        help='The JWT to validate.')
    main(parser.parse_args())
