from flask import Flask
from flask import request
import werkzeug.exceptions as exceptions
import base64
import threading
import secret
import hashlib

import verifier

app = Flask(__name__)

jwtverifier = verifier.JWTVerifier()

# To manually bootstrap a jwks in the server, uncomment this.
# with open("jwks.json") as f:
#     jwks = f.read().strip()
# jwtverifier.register(jwks, {"region":"US"})

### CONST ###
auth_header = 'Authorization'
secret_key_var = "secretKey"
secret_val_var = "secretVal"
jwks_var = "jwks"

if __name__ == '__main__':
    app.run(debug=True,host='0.0.0.0')

sec_store = secret.SecretStore()

@app.route('/')
def index():

    if auth_header not in request.headers:
        raise exceptions.BadRequest("No Auth header exists")

    hdr = request.headers[auth_header].strip()
    if not hdr.startswith("Bearer"):
        raise exceptions.BadRequest("Unexpected auth type")

    spl = hdr.split()
    if len (spl) != 2:
        raise exceptions.BadRequest("Unexpected bearer format")

    token = spl[1]
    claims = jwtverifier.getClaims(token)
    if not claims:
        raise exceptions.Unauthorized("Unable to authenticate JWT token")

    return "JWT Claims: " + str(claims) + "\n"

@app.route('/get/<secretKey>')
def get(secretKey):
    global sec_store

    if auth_header not in request.headers:
        raise exceptions.BadRequest("No Auth header exists")

    hdr = request.headers[auth_header].strip()
    if not hdr.startswith("Bearer"):
        raise exceptions.BadRequest("Unexpected auth type")

    spl = hdr.split()
    if len (spl) != 2:
        raise exceptions.BadRequest("Unexpected bearer format")

    token = spl[1]
    claims = jwtverifier.getClaims(token)
    if not claims:
        raise exceptions.Unauthorized("Unable to authenticate JWT token")

    print claims
    result = sec_store.getSecret(secretKey, claims)
    if result:
        return str(result)
    else:
        raise exceptions.NotFound("Claims did not match any secret policy: " + str(claims))


# Adds a secret
@app.route('/add')
def add():
    args = request.args.copy()
    if secret_key_var not in args or secret_val_var not in args:
        raise exceptions.BadRequest("Invalid addition, secret name or value not specified")

    key = args[secret_key_var]
    val = args[secret_val_var]
    del(args[secret_key_var])
    del(args[secret_val_var])
    claims = args

    global sec_store
    print claims
    sec_store.addSecret (key, val, claims)

    return "Created secret {}: {} with claims {}".format(key, val, str(claims))


# Register a jwks with a set of metadata claims
@app.route('/register')
def register():
    args = request.args.copy()
    if jwks_var not in args:
        raise exceptions.BadRequest("Invalid registration, jwks not specified")

    try:
        print args[jwks_var].strip()
        jwks = base64.b64decode(args[jwks_var].strip())
    except TypeError:
        raise exceptions.BadRequest("Invalid base64 decoding of jwks")

    del(args[jwks_var])
    claims = args

    global jwtverifier
    jwtverifier.register(jwks, claims)
    jwkshash =  hashlib.sha256(jwks).hexdigest()
    return "Registered jwks (sha256:{}) with claims {}".format(jwkshash, str(claims))
