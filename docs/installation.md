# Guía de Instalación y Configuración - HMS

Esta guía cubre la instalación completa de HMS en tu servidor desde cero hasta tener servicios ejecutándose, con especial énfasis en la configuración del archivo `config.toml`.

## 📋 Requisitos Previos

### Hardware Mínimo
- **CPU**: 2+ cores (4+ recomendado para media)
- **RAM**: 4 GB mínimo (8-16 GB recomendado)
- **Almacenamiento**: 50 GB disponibles mínimo (más si usas stacks de media)

### Sistemas Operativos Soportados
- ✅ **macOS** (Intel y Apple Silicon)
- ✅ **Linux** (Ubuntu 20.04+, Debian 11+, Fedora, Arch, etc.)
- ❌ **Windows** (requiere WSL2, soporte experimental)

### Software Requerido

#### Docker (obligatorio)
- **macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop) (v4.0+)
- **Linux**: Docker Engine (v20.10+) y Docker Compose Plugin (v2.0+)

Para verificar la instalación:
```bash
docker --version          # Debe mostrar 20.10+ o superior
docker compose version    # Debe mostrar 2.0+ o superior
```

**Instalación de Docker en Linux:**
```bash
# Script automático (recomendado)
./scripts/install-docker.sh

# O instalación manual
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
```

#### Python (solo para desarrollo)
- Python 3.11+ con `uv` (no requerido para uso normal, solo desarrollo)

### Conexión y Permisos
- Usuario con permisos para ejecutar Docker (grupo `docker`)
- Conexión a Internet para descargar imágenes Docker
- Acceso SSH al servidor (si es remoto)

## 🔧 Instalación Paso a Paso

### Paso 1: Descargar HMS

```bash
# Opción A: Clonar desde repositorio git
git clone <url-repositorio> ~/home-server
cd ~/home-server

# Opción B: Descargar archivo ZIP
# Descargar, extraer y navegar a la carpeta
```

### Paso 2: Ejecutar Script de Instalación

```bash
# Dar permisos de ejecución
chmod +x install.sh

# Ejecutar instalación
./install.sh
```

**Qué hace el script de instalación:**
- ✅ Verifica requisitos (Docker)
- ✅ Crea estructura de directorios necesarios
- ✅ Crea/actualiza `config.toml` con valores auto-detectados:
  - `host_root`: Ruta al proyecto (detectada automáticamente)
  - `puid`: Tu ID de usuario (con `id -u`)
  - `pgid`: Tu ID de grupo (con `id -g`)
  - `docker_gid`: ID del grupo docker (con `getent group docker`)
  - `tz`: Zona horaria del sistema
- ✅ Crea symlink de comando `hms` en `~/.local/bin/`
- ✅ Verifica que `~/.local/bin` esté en tu PATH

### Paso 3: Configurar config.toml

El archivo `config.toml` es el corazón de HMS. El script de instalación ya configuró los valores básicos, **solo necesitas añadir tu dominio**.

#### Abrir el Archivo de Configuración

```bash
# Con tu editor preferido
nano config.toml        # GNU nano (más simple)
vim config.toml         # vim (avanzado)
code config.toml        # VS Code (interfaz gráfica)
```

#### Añadir tu Dominio

Busca la sección `[global]` y añade tu dominio:

```toml
[global]
# ...valores auto-configurados...

# ⚠️ AÑADE ESTA LÍNEA:
domain = "tudominio.com"
```

Ejemplos de dominios:
- `miservidor.duckdns.org` (DuckDNS)
- `miserv.hopto.org` (No-IP)
- `servidor.tudominio.com` (dominio propio)

> **⚠️ Importante**: El stack `infra` es **obligatorio** para que HMS funcione correctamente. Debes configurar también Cloudflare y OAuth (Google). Ver la [Configuración Obligatoria](#-configuración-obligatoria) más abajo.

## 📝 Configuración Detallada del config.toml

### ⚠️ Configuración Obligatoria

El archivo `config.default.toml` ya contiene toda la estructura y valores por defecto. El script `install.sh` configura automáticamente algunos valores. **Solo necesitas añadir manualmente lo siguiente:**

#### 1. Valores Auto-configurados por `install.sh` ✅

Estos ya están configurados después de ejecutar `./install.sh`:
- `host_root` - Ruta al proyecto
- `puid` / `pgid` - IDs de usuario y grupo  
- `docker_gid` - ID del grupo docker
- `tz` - Zona horaria

#### 2. Valores que DEBES Configurar Manualmente ⚠️

```toml
[global]
# Tu dominio (sin http:// o www)
domain = "tudominio.com"  # Ejemplo: miservidor.duckdns.org

[infra.cloudflare]
# Email de tu cuenta Cloudflare
email = "tu-email@ejemplo.com"
# Token API con permisos de DNS (ver guía abajo)
dns_api_token = "tu-token-cloudflare"

[infra.auth]
# Credenciales de Google OAuth (ver guía abajo)
google_client_id = "tu-client-id.apps.googleusercontent.com"
google_client_secret = "tu-client-secret"
# Lista de emails autorizados (separados por comas)
oauth_whitelist = "tu-email@gmail.com"

[infra.watchtower]
# URL de notificaciones (Discord, Telegram, Slack, etc.)
notification_url = "discord://webhook-token@webhook-id"
```

#### 3. Notificaciones del Daemon HMS (Opcional) 🔔

El daemon HMS puede enviarte notificaciones (arranque, parada, jobs fallidos) a través de cualquier servicio soportado por [Apprise](https://github.com/caronc/apprise):

```toml
[global]
# Telegram: obtén BOT_TOKEN con @BotFather y CHAT_ID con /getUpdates
notification_url = "tgram://BOT_TOKEN/CHAT_ID"

# Discord webhook
# notification_url = "discord://TOKEN@WEBHOOK_ID"
```

Si `notification_url` está vacío o no definido, las notificaciones están desactivadas.

> **Nota**: Esta es la URL de notificaciones del **daemon HMS** (backups, errores de jobs). La URL de `[infra.watchtower]` es independiente y controla las notificaciones de actualizaciones de contenedores Docker.

#### 4. Configuración Opcional (Ya tiene valores por defecto) 🔧

El archivo `config.default.toml` ya incluye configuración por defecto para:
- ✅ Backups automáticos diarios (3 AM)
- ✅ Actualización de DNS cada 30 minutos
- ✅ Actualizaciones automáticas de contenedores (cada 12 horas)
- ✅ Exclusiones de backup para stacks media/home
- ✅ Aceleración hardware desactivada (media)

> **💡 Consulta**: Si necesitas modificar valores opcionales, revisa el archivo [`config.default.toml`](../config.default.toml) para ver todas las opciones disponibles.

### 📖 Guías para Obtener Credenciales

#### Cloudflare API Token

1. Ir a [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Perfil → API Tokens → Create Token
3. Usar plantilla **"Edit zone DNS"**
4. Seleccionar tu zona (dominio)
5. Copiar el token generado

#### Google OAuth (TinyAuth)

1. Ir a [Google Cloud Console](https://console.cloud.google.com/)
2. Crear proyecto o seleccionar existente
3. **APIs y servicios** → **Credenciales** → **Crear credenciales** → **ID de cliente OAuth 2.0**
4. Tipo: **Aplicación web**
5. URIs de redireccionamiento autorizadas:
   - `https://auth.{tu-dominio}/callback`
   - `https://auth.{tu-dominio}/auth`
6. Copiar **Client ID** y **Client Secret**

#### Webhook de Discord (Watchtower)

1. Ir a tu servidor Discord → Configuración del canal → Integraciones
2. Crear webhook
3. Copiar URL del webhook
4. Formato para config: `discord://webhook-token@webhook-id`
   - Extraer de la URL: `https://discord.com/api/webhooks/{webhook-id}/{webhook-token}`

> **ℹ️ Otras opciones de notificación**: Ver [documentación de Shoutrrr](https://containrrr.dev/shoutrrr/) para Telegram, Slack, email, etc.

### ✅ Ejemplo de config.toml Mínimo

```toml
[global]
# ✅ Auto-configurado por install.sh
host_root = "/Users/usuario/home-server"
puid = "1000"
pgid = "1000"
docker_gid = "999"
tz = "Europe/Madrid"
log_level = "info"

# ⚠️ AÑADE MANUALMENTE
domain = "miservidor.duckdns.org"

[infra.cloudflare]
email = "mi-email@gmail.com"
dns_api_token = "abc123xyz789token"

[infra.auth]
google_client_id = "123456789-abc.apps.googleusercontent.com"
google_client_secret = "GOCSPX-abcdef123456"
oauth_whitelist = "mi-email@gmail.com"

[infra.watchtower]
notification_url = "discord://token@id"

# ... el resto de secciones vienen de config.default.toml
```

### Paso 4: Iniciar el Sistema HMS

```bash
# Iniciar el servidor HMS
# Esto automáticamente levanta el stack 'infra' primero
# y luego levanta cualquier otro stack marcado como habilitado en config.toml
hms start
```

**Qué hace `hms start`:**
1. ✅ Valida la configuración global
2. ✅ **Levanta el stack `infra` automáticamente** (siempre primero)
3. ✅ Levanta otros stacks marcados como `enabled = true` en config.toml
4. ✅ Inicia el scheduler de tareas programadas

> **💡 Nota**: Por defecto, solo `infra` está habilitado. Los demás stacks (media, necesse, etc.) debes levantarlos manualmente con `hms <stack> up` o habilitarlos en config.toml.

### Paso 5: Verificar Stack de Infraestructura

El stack de infraestructura ya fue levantado automáticamente por `hms start`. Ahora verifica que esté funcionando:

```bash
# Ver estado del stack infra
hms infra info

# Esperar a que todos los servicios estén saludables (30-60 segundos)
# Los servicios deben mostrar estado "Up" o "running"

# Verificar logs si hay algún problema
hms logs infra -f
```

**Servicios incluidos en infra:**
- 🌐 **Traefik**: Proxy inverso y SSL automático (`https://traefik.{tu-dominio}`)
- 🔄 **Watchtower**: Actualizaciones automáticas de contenedores
- 🔐 **TinyAuth**: Autenticación OAuth (`https://auth.{tu-dominio}`)

### Paso 6: Desplegar Stacks Adicionales

Una vez que infra está ejecutándose correctamente, puedes levantar otros stacks:

```bash
# Ver todos los stacks disponibles
hms list

# Levantar stack de media (Jellyfin, Radarr, Sonarr, etc.)
hms up media

# Levantar stack de Necesse (servidor de juego)
hms up necesse

# Levantar stack home (dashboard HMS)
hms up home
```

### Paso 7: Acceder a los Servicios

Los servicios están disponibles en:

```
https://servicio.{tu-dominio}
```

**Ejemplos** (con dominio `miservidor.duckdns.org`):
- Traefik Dashboard: `https://traefik.miservidor.duckdns.org`
- Jellyfin: `https://jellyfin.miservidor.duckdns.org`
- Radarr: `https://radarr.miservidor.duckdns.org`
- qBittorrent: `https://qbittorrent.miservidor.duckdns.org`

**Servicios protegidos con TinyAuth:**
La mayoría de servicios administrativos requieren autenticación OAuth con tu cuenta de Google (debe estar en `oauth_whitelist`).
