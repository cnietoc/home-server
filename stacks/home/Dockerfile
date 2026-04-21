FROM node:22-alpine

# Instalar herramientas del sistema necesarias
RUN apk add --no-cache \
    docker-cli \
    procps \
    util-linux \
    coreutils \
    curl \
    su-exec

# Crear directorio de la aplicación
WORKDIR /app

# Copiar archivos de dependencias primero para mejor cache
COPY package*.json ./

# Instalar dependencias como root
RUN npm ci --omit=dev && \
    npm cache clean --force

# Copiar código de la aplicación
COPY server.js ./
COPY public/ ./public/

# Copiar script de entrada
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Exponer puerto
EXPOSE 3000

ENV NODE_ENV=production \
    PORT=3000

# Usar entrypoint para manejo dinámico de usuarios
ENTRYPOINT ["/entrypoint.sh"]
CMD ["npm", "start"]
