# Configuración de Autenticación con Authelia

## Pasos de Configuración

### 1. Generar Secretos de Seguridad

Ejecuta estos comandos para generar las claves necesarias:

```bash
# Generar secreto JWT (para tokens)
openssl rand -hex 32

# Generar secreto de sesión  
openssl rand -hex 32

# Generar clave de cifrado de almacenamiento
openssl rand -hex 32
```

### 2. Generar Hash de Contraseña

Usa el script de ayuda para generar el hash:
```bash
./scripts/generate-auth-password.sh
```

### 3. Configurar Variables de Entorno

Edita el archivo de configuración:
```bash
nano config/private/auth.env
```

Agrega toda la configuración:
```bash
# Secretos de Authelia
AUTHELIA_JWT_SECRET=tu-jwt-secret-de-64-caracteres
AUTHELIA_SESSION_SECRET=tu-session-secret-de-64-caracteres  
AUTHELIA_STORAGE_ENCRYPTION_KEY=tu-storage-key-de-64-caracteres

# Base de datos de usuarios en formato YAML inline
AUTHELIA_USERS_DATABASE="users:
  admin:
    displayname: Administrator
    password: \$argon2id\$v=19\$m=65536,t=3,p=4\$TU_HASH_GENERADO_AQUI
    email: admin@tu-dominio.com
    groups:
      - admins"
```

### 4. Desplegar Autenticación

```bash
# Regenerar archivos .env
./scripts/deploy.sh --force-envs

# Desplegar stack de autenticación
./scripts/deploy.sh auth --verbose

# Redesplegar network con autenticación habilitada
./scripts/deploy.sh network --verbose
```

### 5. Acceder a los Servicios

- **Panel de autenticación**: https://auth.tu-dominio.com
- **Dashboard de Traefik**: https://traefik.tu-dominio.com (ahora requiere login)

### 6. Configurar Otros Servicios

Para proteger cualquier servicio con autenticación, agrega esta etiqueta:
```yaml
labels:
  - "traefik.http.routers.tu-servicio.middlewares=authelia@docker"
```

## Flujo de Autenticación

1. Usuario intenta acceder a https://traefik.tu-dominio.com
2. Traefik redirige a https://auth.tu-dominio.com para login
3. Usuario se autentica en Authelia
4. Authelia redirige de vuelta al servicio original
5. Usuario accede al servicio protegido

## Configuración Avanzada

### Agregar Más Usuarios

Para agregar usuarios adicionales, edita `config/private/auth.env` y expande `AUTHELIA_USERS_DATABASE`:

```bash
AUTHELIA_USERS_DATABASE="users:
  admin:
    displayname: Administrator
    password: \$argon2id\$v=19\$m=65536,t=3,p=4\$HASH_ADMIN
    email: admin@tu-dominio.com
    groups:
      - admins
  usuario1:
    displayname: Usuario Uno
    password: \$argon2id\$v=19\$m=65536,t=3,p=4\$HASH_USER1
    email: usuario1@tu-dominio.com
    groups:
      - users"
```

### Políticas de Acceso Personalizadas

Para cambiar las políticas de acceso, edita `docker/auth/docker-compose.yml` y modifica las variables:

```yaml
environment:
  # Regla para administradores en todos los servicios
  - AUTHELIA_ACCESS_CONTROL_RULES_0_DOMAIN=*.${BASE_DOMAIN}
  - AUTHELIA_ACCESS_CONTROL_RULES_0_POLICY=one_factor
  - AUTHELIA_ACCESS_CONTROL_RULES_0_SUBJECT=group:admins
  
  # Regla para servicio específico con usuarios normales
  - AUTHELIA_ACCESS_CONTROL_RULES_1_DOMAIN=app.${BASE_DOMAIN}
  - AUTHELIA_ACCESS_CONTROL_RULES_1_POLICY=one_factor
  - AUTHELIA_ACCESS_CONTROL_RULES_1_SUBJECT=group:users
  
  # Servicios públicos (sin autenticación)
  - AUTHELIA_ACCESS_CONTROL_RULES_2_DOMAIN=hello.${BASE_DOMAIN}
  - AUTHELIA_ACCESS_CONTROL_RULES_2_POLICY=bypass
```

### 2FA con TOTP

Ya está habilitado automáticamente. Los usuarios pueden:
1. Acceder al panel de Authelia en https://auth.tu-dominio.com
2. Ir a "Configuración" 
3. Configurar 2FA con Google Authenticator o similar

### Configuración de Sesión

Para cambiar duración de sesiones, edita las variables en `docker/auth/docker-compose.yml`:

```yaml
environment:
  - AUTHELIA_SESSION_EXPIRATION=24h          # Sesión expira en 24h
  - AUTHELIA_SESSION_INACTIVITY=2h           # Inactividad máxima 2h  
  - AUTHELIA_SESSION_REMEMBER_ME_DURATION=1M # "Recordarme" por 1 mes
```

## Troubleshooting

### Ver logs de Authelia
```bash
docker compose -f docker/auth/docker-compose.yml logs -f authelia
```

### Verificar configuración
```bash
# Ver variables de entorno cargadas
docker compose -f docker/auth/docker-compose.yml exec authelia env | grep AUTHELIA
```

### Resetear contraseña de usuario
```bash
# 1. Generar nuevo hash
./scripts/generate-auth-password.sh

# 2. Editar config/private/auth.env
# Reemplazar el hash en AUTHELIA_USERS_DATABASE

# 3. Regenerar .env y redesplegar
./scripts/deploy.sh --force-envs
./scripts/deploy.sh auth --verbose
```

### Problemas Comunes

#### Usuario no puede acceder
- Verificar que el hash de contraseña sea correcto
- Comprobar que el usuario esté en el grupo correcto (`admins`)
- Revisar logs para errores específicos

#### Redirección infinita
- Verificar que el middleware esté correctamente configurado en el servicio
- Comprobar que las URLs de redirección sean correctas

#### Sesión se pierde constantemente  
- Revisar configuración de Redis
- Verificar que `AUTHELIA_SESSION_SECRET` sea consistente

