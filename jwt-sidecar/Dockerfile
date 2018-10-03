FROM python:2.7.10
RUN apt-get update && \
    apt-get -y install gcc vim curl && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /
RUN pip install -r /requirements.txt && \
    rm -f /requirements.txt

COPY gen-jwt.py /
