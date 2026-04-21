FROM node:22-alpine

RUN apk add --no-cache curl

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY server.js ./
COPY public/ ./public/

EXPOSE 3000
ENV NODE_ENV=production PORT=3000

CMD ["node", "server.js"]
