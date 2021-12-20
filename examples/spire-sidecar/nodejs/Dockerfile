FROM node:stretch-slim
WORKDIR /usr/src/app
COPY ./nodejs/package*.json ./

RUN npm install
# If you are building your code for production
# RUN npm ci --only=production

COPY ./nodejs .

EXPOSE 8080

CMD [ "node", "index.js" ]