FROM node:18-alpine

# Instalar herramientas del sistema necesarias
RUN apk add --no-cache \
    docker-cli \
    procps \
    util-linux \
    coreutils

# Crear usuario no-root primero
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Crear directorio de la aplicación
WORKDIR /app

# Copiar archivos de dependencias (mejor cache de Docker)
COPY package*.json ./

# Instalar dependencias como root, luego cambiar permisos
RUN npm ci --omit=dev && \
    npm cache clean --force

# Copiar código de la aplicación
COPY . .

# Cambiar permisos de todo el directorio
RUN chown -R nodejs:nodejs /app

# Cambiar a usuario no-root
USER nodejs

# Exponer puerto
EXPOSE 3000

# Variables de entorno
ENV NODE_ENV=production \
    PORT=3000

# Comando de inicio
CMD ["npm", "start"]
