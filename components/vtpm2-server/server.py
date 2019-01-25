from flask import Flask
from flask import request
#import threading
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
    with open("%s/tpmkeyurl" % statedir) as f:
        tpmkey = f.read().strip()
        print tpmkey
    out = subprocess.check_output(['/usr/local/bin/gen-jwt.py',tpmkey,'--iss','example-issuer', claims])
    return str(out)

@app.route('/getJWKS')
def getJWKS():
    statedir = os.getenv('STATEDIR') or '/tmp'
    with open("%s/tpmkeyurl" % statedir) as f:
        tpmkey = f.read().strip()
    out = subprocess.check_output(['/usr/local/bin/gen-jwt.py',tpmkey,'--jwks','/tmp/jwks.json'])
    with open("/tmp/jwks.json") as f:
        jwks = f.read().strip()
        print jwks
        return str(jwks)
    return str(out)
