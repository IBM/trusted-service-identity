from flask import Flask, request
import os
from os.path import join, exists
import subprocess

app = Flask(__name__)

if __name__ == '__main__':
    app.run(debug=True,host='0.0.0.0',port=5000)

@app.route('/')
def index():
    return "JSS for vTPM - pub"

# public server returns the CSR for signing with CA to create X5c
@app.route('/public/getCSR')
def getCSR():
    statedir = os.getenv('STATEDIR') or '/tmp'
    csrfile = join(statedir,"server.csr")
    try:
        with open(csrfile) as f:
            csr = f.read().strip()
            return str(csr)
    except Exception as e:
        print (e)
        #flash(e)
        return ("Error %s" % e), 500

# public server allows posting X5c. After this file is successfully stored,
# this public server shuts down
@app.route('/public/postX5c', methods=["POST"])
def postX5c():
    try:
        statedir = os.getenv('STATEDIR') or '/tmp'
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
