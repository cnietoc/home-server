FROM node:18-alpine

# Instalar herramientas del sistema necesarias
RUN apk add --no-cache \
    docker-cli \
    procps \
    util-linux \
    coreutils \
    curl

# Crear usuario no-root primero
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

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

# Debug: verificar estructura de archivos
RUN echo "=== Estructura de /app ===" && \
    ls -la /app/ && \
    echo "=== Estructura de /app/public ===" && \
    ls -la /app/public/ && \
    echo "=== Contenido de server.js (primeras 10 líneas) ===" && \
    head -10 /app/server.js

# Cambiar permisos
RUN chown -R nodejs:nodejs /app

# Cambiar a usuario no-root
USER nodejs

# Exponer puerto
EXPOSE 3000

# Variables de entorno
ENV NODE_ENV=production \
    PORT=3000

# Verificar que Node.js puede iniciar (test básico)
RUN node --version && npm --version

# Comando de inicio con logging mejorado
CMD ["sh", "-c", "echo 'Iniciando servidor Node.js en puerto $PORT' && npm start"]
