from flask import Flask, request
import os
from os.path import join, exists
import subprocess

app = Flask(__name__)

if __name__ == '__main__':
    app.run(debug=True,host='0.0.0.0')

@app.route('/')
def index():
    return "JSS pub server"

@app.route('/public/getCSR')
def getCSR():
    statedir = os.getenv('STATEDIR') or '/host/tsi-secure'
    csrfile = join(statedir,"server.csr")
    with open(csrfile) as f:
        csr = f.read().strip()
        return str(csr)

@app.route('/public/postX5c', methods=["POST"])
def postX5c():
    try:
        statedir = os.getenv('STATEDIR') or '/host/tsi-secure'
        x5cfile = join(statedir, "x5c")
        # if file already exists, don't all to override it
        if exists(x5cfile):
            # return 403 Forbidden, 406 Not Accesptable or 409 Conflict
            return "File already exists.", 403
        if request.data and len(request.data) > 0:
            with open(x5cfile, "w+") as f:
                f.write(request.data)
                f.close()
                return "Upload of x5c successful"
    except Exception as e:
        print (e)
        #flash(e)
        return ("Error %s" % e), 500
