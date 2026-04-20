# Documentación de Stacks - HMS

Guía completa sobre todos los stacks disponibles.

## 📚 ¿Qué es un Stack?

Un **stack** es un grupo de servicios Docker relacionados que se despliegan juntos como una unidad.

## 🗂️ Stacks Disponibles

| Stack | Estado | Descripción | Servicios |
|-------|--------|-------------|-----------|
| **infra** | ✅ Estable | Infraestructura base | Traefik, TinyAuth, Watchtower |
| **media** | ✅ Estable | Multimedia | Jellyfin, Radarr, Sonarr |
| **necesse** | ✅ Estable | Servidor juego | Necesse |
| **corekeeper** | ✅ Estable | Servidor juego | Core Keeper |
| **terraria** | ✅ Estable | Servidor juego | Terraria con tModLoader |
| **vrising** | ✅ Estable | Servidor juego | V Rising |
| **home** | ✅ Estable | Dashboard de servicios | Página de inicio HMS |
| **steam** | 🚧 Construcción | ArchiSteamFarm | Farmeo de cromos Steam |
| **helloworld** | 📚 Ejemplo | Demo | Nginx |

## 📊 Anatomía de un Stack

Cada stack tiene **dos carpetas principales**:

### 1. 📄 Definición → `stacks/mystack/`

Contiene la definición del stack (código):

```
stacks/mystack/
├── docker-compose.yml           # Servicios Docker (requerido)
├── pre-deploy.sh                # Script previo bash (opcional)
└── pre-deploy.py                # Script previo python (opcional)
```

### 2. 💾 Datos → `data/mystack/`

Carpeta creada automáticamente para almacenar todos los datos persistentes del stack.

**Variables de entorno disponibles:**
- `${STACK_DATA}` → ruta completa a `data/mystack/`
- `${STACK_PREFIX}` → nombre del stack (ej: `mystack`)

**⚠️ Recomendación: NO usar volúmenes Docker con nombre**

En lugar de usar volúmenes Docker con nombre, se recomienda usar **bind mounts** directamente a `${STACK_DATA}`:

**❌ NO recomendado:**
```yaml
volumes:
  config: {}
  database: {}

services:
  myservice:
    volumes:
      - config:/app/config
      - database:/app/db
```

**✅ RECOMENDADO:**
```yaml
services:
  myservice:
    volumes:
      - ${STACK_DATA}/config:/app/config
      - ${STACK_DATA}/database:/app/db
```

**¿Por qué?**
- ✅ **Backups fáciles**: todo en una carpeta `data/mystack/`
- ✅ **Portabilidad**: mueves la carpeta y listo
- ✅ **Visibilidad**: acceso directo a los archivos desde el host
- ✅ **HMS integrado**: los comandos de backup funcionan automáticamente

### Ejemplo Completo

**stacks/mystack/docker-compose.yml**

```yaml
name: ${STACK_PREFIX}

networks:
  hms-network:
    external: true

services:
  myservice:
    image: myimage:latest
    container_name: ${STACK_PREFIX}-myservice
    restart: unless-stopped
    volumes:
      - ${STACK_DATA}/config:/app/config
      - ${STACK_DATA}/data:/app/data
    environment:
      - CONFIG_VAR=value
    networks:
      - hms-network
    labels:
      # Traefik - Exponer en https://myservice.example.com
      traefik.enable: "true"
      traefik.docker.network: "hms-network"
      traefik.http.routers.myservice.rule: "Host(`myservice.${DOMAIN}`)"
      traefik.http.routers.myservice.tls: "true"
      traefik.http.routers.myservice.tls.certresolver: "cloudflare"
      traefik.http.services.myservice.loadbalancer.server.port: "8080"
      # HMS - Descripción para el dashboard
      hms.description: "🚀 Mi servicio personalizado"

x-hms:
  name: mystack
  version: "1.0"
  description: "Mi stack personalizado"
  enabled: true
  services:
    - myservice
```

### Pre-deploy Scripts

Scripts ejecutados antes de `docker-compose up`. Puedes usar **bash** o **Python**:

#### Opción 1: pre-deploy.sh (Bash)

```bash
#!/bin/bash
echo "🔧 Configurando mystack..."
mkdir -p /data/mystack/config
chmod 755 /data/mystack/config
echo "✅ Listo"
```

#### Opción 2: pre-deploy.py (Python)

```python
#!/usr/bin/env python3
"""Pre-deploy para mystack."""
import os
import sys
from pathlib import Path

def main() -> int:
    print("🔧 Configurando mystack...")
    
    config_dir = Path("/data/mystack/config")
    config_dir.mkdir(parents=True, exist_ok=True)
    
    # Generar archivo de configuración dinámicamente
    config_file = config_dir / "app.conf"
    config_file.write_text("server_port=8080\n")
    
    print("✅ Listo")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

**Notas:**
- Si existen ambos, **pre-deploy.sh** tiene prioridad
- El script debe retornar código 0 para éxito
- Tienen acceso a todas las variables de entorno del stack
- Útiles para: crear directorios, generar configs dinámicas, inicializar datos, docker overrides, etc.

## 🔧 Configuración por Stack

Cada stack puede tener su propia sección en `config.toml`:

**Ejemplo:**
```toml
[mystack]
enabled = true
custom_option = "value"
server_port = 8080
```

Consulta la documentación individual de cada stack para ver sus opciones de configuración específicas.

## 🔌 Comandos de Stack

```bash
hms [stack] up              # Levantar
hms [stack] down            # Bajar
hms [stack] info            # Información
hms [stack] logs            # Logs
hms [stack] validate        # Validar
hms [stack] restart         # Reiniciar
```

## 💾 Backups

Cada stack puede hacer backup de su carpeta `data/mystack/` completa. **Por defecto está activado** para todos los stacks.

### Crear Backup de un Stack

```bash
# Backup de un stack específico
hms system backup --stack media

# Resultado: backups/media_20260223-143022.tar.gz
```

### Funcionamiento

1. HMS detiene el stack (`docker-compose down`)
2. Comprime toda la carpeta `data/mystack/` → `backups/mystack_TIMESTAMP.tar.gz`
3. Reinicia el stack (`docker-compose up`)

### Ventajas de usar ${STACK_DATA}

Si usas `${STACK_DATA}` (bind mounts) en lugar de volúmenes Docker:
- ✅ **Backup automático** de todos los datos del stack en un solo `.tar.gz`
- ✅ **Restore simple**: HMS extrae y restaura automáticamente
- ✅ **Sin configuración extra**: funciona out-of-the-box
- ✅ **Rotación automática**: mantiene solo los últimos N backups

Si usas volúmenes Docker con nombre, tendrás que hacer backup manual con `docker volume`.

### Configuración de Backups

```toml
# config.toml

[global.backups]
max_backups = 5                  # Máximo de backups por stack (default: 5)

[media.backups]
enabled = true                   # Activado por defecto
exclude = ["downloads/*"]        # Patterns a excluir (opcional)
```

**Ubicación:** `backups/[stack]_[timestamp].tar.gz`

## 🔗 Networking

Los stacks utilizan redes Docker para comunicación:

- **`hms-network`** (external): Red compartida entre todos los stacks
- **`${STACK_PREFIX}-network`**: Red interna opcional de cada stack (ej: `media_internal`)

### Exponer Servicios con Traefik

Para que un servicio sea accesible por HTTP/HTTPS a través de un subdominio, usa **labels de Traefik**:

```yaml
services:
  myservice:
    image: myimage:latest
    container_name: ${STACK_PREFIX}-myservice
    networks:
      - hms-network
    labels:
      # Habilitar Traefik
      traefik.enable: "true"
      traefik.docker.network: "hms-network"
      
      # Configurar router (nombre único: myservice)
      traefik.http.routers.myservice.rule: "Host(`myservice.${DOMAIN}`)"
      traefik.http.routers.myservice.tls: "true"
      traefik.http.routers.myservice.tls.certresolver: "cloudflare"
      
      # Puerto del servicio
      traefik.http.services.myservice.loadbalancer.server.port: "8080"
```

**Acceso:** `https://myservice.example.com` (donde `example.com` es tu `${DOMAIN}`)

### 🔐 Proteger con Autenticación OAuth (Google)

Para requerir autenticación con Google OAuth antes de acceder al servicio, agrega el **middleware `tinyauth`**:

```yaml
services:
  myservice:
    image: myimage:latest
    container_name: ${STACK_PREFIX}-myservice
    networks:
      - hms-network
    labels:
      traefik.enable: "true"
      traefik.docker.network: "hms-network"
      traefik.http.routers.myservice.rule: "Host(`myservice.${DOMAIN}`)"
      traefik.http.routers.myservice.tls: "true"
      traefik.http.routers.myservice.tls.certresolver: "cloudflare"
      # 🔐 AGREGAR ESTA LÍNEA para proteger con OAuth
      traefik.http.routers.myservice.middlewares: "tinyauth@docker"
      traefik.http.services.myservice.loadbalancer.server.port: "8080"
```

**¿Qué hace?**
- Intercepta todas las peticiones al servicio
- Redirige a `https://auth.${DOMAIN}` para login con Google
- Solo permite acceso si el email está en la whitelist configurada
- Mantiene la sesión autenticada

**Configuración requerida en `config.toml`:**

```toml
[infra.auth]
google_client_id = "tu-client-id.apps.googleusercontent.com"
google_client_secret = "tu-client-secret"
oauth_whitelist = ["tu-email@gmail.com", "otro-email@gmail.com"]
```

**Ejemplos reales:**
- Stack **media**: Todos los servicios protegidos (Radarr, Sonarr, qBittorrent)
- Stack **infra**: Dashboard de Traefik protegido

**Servicios públicos (sin middleware):**
- Jellyfin (acceso público para streaming)
- Home dashboard (página de inicio)

**Notas:**
- El servicio **debe estar en la red `hms-network`**
- El nombre del router (`myservice` en el ejemplo) debe ser **único** en todo HMS
- Traefik automáticamente obtiene certificados SSL de Cloudflare
- `${DOMAIN}` se define en las variables de entorno del stack

**Ejemplo sin protección:**
```yaml
# Acceso público: https://public.example.com
traefik.http.routers.public.rule: "Host(`public.${DOMAIN}`)"
# (sin línea de middlewares)
```

**Ejemplo con protección OAuth:**
```yaml
# Acceso protegido: https://private.example.com
traefik.http.routers.private.rule: "Host(`private.${DOMAIN}`)"
traefik.http.routers.private.middlewares: "tinyauth@docker"
```

## 🚀 Crear Nuevo Stack

1. Crear carpeta: `stacks/mystack/`
2. Crear `docker-compose.yml`
3. Crear script de pre-deploy (opcional)
4. Añadir a `config.toml` o  `config.default.toml`
5. Probar: `hms up mystack`
