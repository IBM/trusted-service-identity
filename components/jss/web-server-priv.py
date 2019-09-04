from flask import Flask, request
import os
from os.path import join, exists
import subprocess

app = Flask(__name__)

if __name__ == '__main__':
    app.run(debug=True,host='0.0.0.0',port=5001)

@app.route('/')
def index():
    return "JSS priv server"

@app.route('/getJWT')
def get():
    args = request.args.copy()
    claims = ""
    if args:
        claims = "--claims="
        for k in args:
            claims = claims + k + ":" + args[k] + "|"
    statedir = os.getenv('STATEDIR') or '/host/tsi-secure'
    privkeyfile = join(statedir, "private.key")
    try:
        out = subprocess.check_output(['/usr/local/bin/gen-jwt.py',privkeyfile, claims])
        return str(out)
    except Exception as e:
        print e.output
        return ("Error: %s" % e.output), 503
