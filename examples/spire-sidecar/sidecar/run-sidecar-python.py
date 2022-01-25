import os
import time
import subprocess
import requests
import json
import base64
import sys
from functools import reduce
from decouple import config


# read enviroment variable
SOCKETFILE=os.getenv('SOCKETFILE') 
if (SOCKETFILE is None): 
    # if the enviroment variable is not set, try to read from .env file 
    # .env file mode for testing
    SOCKETFILE = config('SOCKETFILE', default='/run/spire/sockets/agent.sock')

CFGDIR=os.getenv('CFGDIR')
if (CFGDIR is None):
    CFGDIR = config('CFGDIR', default='/run/db')

ROLE=os.getenv('ROLE')
if (ROLE is None):
    ROLE = config('ROLE', default='dbrole1')

VAULT_ADDR=os.getenv('VAULT_ADDR')
if (VAULT_ADDR is None):
    VAULT_ADDR = config('VAULT_ADDR', default='http://tsi-vault.my-cluster-0123456789-0000.eu-de.containers.appdomain.cloud')

TIMEOUT=0.5 # 30 sec

# method used to obtain a resource/file from vault, using jwt token (i.e. X-Vault-Token)
def getfile(filename, filePath, token):
    try:
        headers = {'X-Vault-Token': token}
        url = VAULT_ADDR + "/v1/secret/data/" + filePath + ("" if filePath.endswith('/') else "/") + filename
        response = requests.get(url, headers=headers)
        obj=json.loads(response.text)
        with open(CFGDIR + ("" if CFGDIR.endswith('/') else "/") + filename, "w") as f:
            if (filename.upper().endswith(".JSON")):
                data = obj["data"]["data"]
                # JSON dump, if not we need to cast to string
                f.write(json.dumps(data))
            else:
                # other files, beside JSON, need to be encoded to base64 prior to storing into Vault
                data = base64.b64decode(obj["data"]["data"]["sha"]).decode() # force cast to string
                f.write(data)
        return True
    except Exception as e:
        print("Error at file retrieval:", e)
        return False

# Method used to obtain a dictionary with the file name as the key and the path as the value (i.e. {filename:path})
def arraytodict(a, b):
    splitvalue = b.split("/")
    filename = splitvalue.pop().strip() # get last element
    path = "/".join(splitvalue) # joins path parts
    a[filename] = path
    return a

if __name__ == "__main__":
    # sanity check for input file
    if len(sys.argv) == 0:
        print("No input file was provided")
        exit(1)
    inputfile = sys.argv[1]
    # sanity check if input file exists
    if not os.path.exists(inputfile):
        print("Input file was not found")
        exit(1)
    with open(inputfile, 'r') as f:
        files = f.readlines()
    # convert file to dictionary
    listOfFile = reduce(arraytodict, files, {})

    while True:
        # make sure the socket file exists before requesting a token
        while not os.path.exists(SOCKETFILE):
            time.sleep(0.08)

        # obtain identity from spire server
        output = subprocess.check_output(["/opt/spire/bin/spire-agent", "api", "fetch", "jwt", "-audience", "vault", "-socketPath", SOCKETFILE])
        token = output.split()[1].decode() # supress bytes/cast to string

        # Vault URL for identity check
        authurl = VAULT_ADDR+"/v1/auth/jwt/login"
        # data load for the request
        authdata = {"jwt": token, "role": ROLE}

        authresponse = requests.post(url = authurl, data = authdata, timeout=10)
        obj=json.loads(authresponse.text)
        # Vault token
        VAULT_TOKEN=obj["auth"]["client_token"]

        success = True
        # check if all files were retrieved
        for file, path in listOfFile.items():
            getfile(file, path, VAULT_TOKEN)
            foundfile = os.path.exists(CFGDIR+"/"+file)
            if not foundfile:
                print("File was not found $s.", file)
            success = success and foundfile
        
        if success:
            exit()

        time.sleep(TIMEOUT)