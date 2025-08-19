FROM node:22-alpine

RUN apk add openssl

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 8080

USER node

CMD ["npm", "start"]
