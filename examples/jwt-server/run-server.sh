#!/bin/sh
curl -LO ${JWKS} && \
FLASK_APP=/server.py python -m flask run --host=0.0.0.0
