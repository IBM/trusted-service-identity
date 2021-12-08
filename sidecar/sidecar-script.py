import os
import time
import subprocess
import requests
import json
import base64
from decouple import config


SOCKETFILE=os.getenv('SOCKETFILE') 
if (SOCKETFILE is None):
    SOCKETFILE = config('SOCKETFILE', default='/run/spire/sockets/agent.sock')

CFGDIR=os.getenv('CFGDIR')
if (CFGDIR is None):
    CFGDIR = config('CFGDIR', default='/run/db')

ROLE=os.getenv('ROLE')
if (ROLE is None):
    ROLE = config('ROLE', default='dbrole1')

VAULT_ADDR=os.getenv('VAULT_ADDR')
if (VAULT_ADDR is None):
    VAULT_ADDR = config('VAULT_ADDR', default='http://tsi-vault-tsi-vault.space-x04-9d995c4a8c7c5f281ce13d5467ff6a94-0000.eu-de.containers.appdomain.cloud')

TIMEOUT=0.5 # 30 sec

def getfile(filename, filePath, token):
    try:
        headers = {'X-Vault-Token': token}
        url = VAULT_ADDR + "/v1/secret/data/" + filePath + ("" if filePath.endswith('/') else "/") + filename
        response = requests.get(url, headers=headers)
        obj=json.loads(response.text)
        with open(CFGDIR + ("" if CFGDIR.endswith('/') else "/") + filename, "w") as f:
            if (filename.upper().endswith(".JSON")):
                data = obj["data"]["data"]
                f.write(json.dumps(data))
            else:
                data = base64.b64decode(obj["data"]["data"]["sha"]).decode()
                f.write(data)
        return True
    except:
        print("Error at file retrieval")
        return False

if __name__ == "__main__":
    while True:

        # make sure the socket file exists before requesting a token
        while not os.path.exists(SOCKETFILE):
            time.sleep(0.08)

        output = subprocess.check_output(["/opt/spire/bin/spire-agent", "api", "fetch", "jwt", "-audience", "vault", "-socketPath", SOCKETFILE])
        token = output.split()[1].decode() # supress bytes

        authurl = VAULT_ADDR+"/v1/auth/jwt/login"
        authdata = {"jwt": token, "role": ROLE}

        authresponse = requests.post(url = authurl, data = authdata, timeout=10)
        obj=json.loads(authresponse.text)
        VAULT_TOKEN=obj["auth"]["client_token"]

        getfile("config.json", "db-config/", VAULT_TOKEN)
        getfile("config.ini", "db-config/", VAULT_TOKEN)

        if os.path.exists(CFGDIR+"/"+"config.json") and os.path.exists(CFGDIR+"/"+"config.ini"):
            exit()

        time.sleep(TIMEOUT)