from flask import Flask
from flask import request
#import threading
import os
from os.path import join
import subprocess

app = Flask(__name__)

if __name__ == '__main__':
    app.run(debug=True,host='0.0.0.0')

@app.route('/')
def index():
    return "TPM wrapper"

@app.route('/getJWT')
def get():
    args = request.args.copy()
    claims = ""
    if args:
        claims = "--claims="
        for k in args:
            claims = claims + k + ":" + args[k] + "|"
    statedir = os.getenv('STATEDIR') or '/tmp'
    tpmkeyfile = join(statedir, "tpmkeyurl")
    with open(tpmkeyfile) as f:
        tpmkey = f.read().strip()
    out = subprocess.check_output(['/usr/local/bin/gen-jwt.py',tpmkey,'--iss','example-issuer', claims])
    return str(out)

@app.route('/getJWKS')
def getJWKS():
    statedir = os.getenv('STATEDIR') or '/tmp'
    tpmkeyfile = join(statedir, "tpmkeyurl")
    with open(tpmkeyfile) as f:
        tpmkey = f.read().strip()
    out = subprocess.check_output(['/usr/local/bin/gen-jwt.py',tpmkey,'--jwks','/tmp/jwks.json'])
    jwksfile = join(statedir, "jwks.json")
    with open(jwksfile) as f:
        jwks = f.read().strip()
        return str(jwks)
    return str(out)


@app.route('/getCSR')
def getCSR():
    statedir = os.getenv('STATEDIR') or '/tmp'
    csrfile = join(statedir,"server.csr")
    with open(csrfile) as f:
        csr = f.read().strip()
        return str(csr)

@app.route('/public/postX5c', methods=["POST"])
def postX5c():


    error = ''
    try:

        statedir = os.getenv('STATEDIR') or '/tmp'
        x5cfile = join(statedir, "x5c")
        if exists(x5cfile):
            return "File already exists."

        new_x5c = request.form['x5c']
        with open(x5cfile, "w+") as f:
            f.write(new_x5c)
        f.close
    except Exception as e:
        #flash(e)
        return "Error "
