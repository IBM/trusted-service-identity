#!/bin/sh
STATEDIR=${STATEDIR:-/host/tsi-secure}
cd /usr/local/bin || exit
FLASK_APP=/web-server-priv.py python -m flask run --host=0.0.0.0 --port=5001
