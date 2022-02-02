FROM python:3.9
ENV PYTHONUNBUFFERED 1
WORKDIR /app
COPY ./python/requirements.txt /app/requirements.txt
RUN pip install -r requirements.txt
COPY ./python /app

CMD python main.py