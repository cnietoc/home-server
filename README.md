# HMS - Home Server Management System

**HMS** es un sistema de gestión centralizado para contenedores Docker enfocado en automatizar el despliegue, configuración y orquestación de múltiples servicios en un servidor doméstico. Proporciona una interfaz CLI intuitiva para gestionar diferentes "stacks" (grupos de servicios relacionados).

## 🎯 Características Principales

- **Gestión de Stacks**: Desplegar múltiples servicios como unidades coherentes
- **CLI Intuitiva**: Interfaz de línea de comandos con comandos globales y por stack
- **Configuración Centralizada**: Archivo TOML único para toda la configuración
- **Sistema de Plugins**: Arquitectura extensible mediante plugins
- **Pre-deploy Scripts**: Scripts bash y Python para configuración previa al despliegue
- **Scheduler Integrado**: Tareas programadas automáticas
- **Gestión de Datos**: Persistencia de datos con directorios separados por stack
- **Docker nativo**: Integración completa con Docker Compose

## 🚀 Quickstart

### Requisitos
- **Docker Desktop** (macOS) o **Docker Engine** (Linux)
- Conexión a Internet

### Instalación Rápida

```bash
# 1. Clonar el repositorio
git clone <tu-repo> ~/home-server
cd ~/home-server

# 2. Ejecutar instalación
chmod +x install.sh
./install.sh

# 3. Configurar (edita config.toml con tus valores)
nano config.toml
```

> **📖 Configuración Detallada**: Para una guía completa sobre todos los valores de configuración disponibles en `config.toml`, consulta la [Guía de Instalación y Configuración](docs/installation.md#-configuración-detallada-del-configtoml).

**El script de instalación ya configuró automáticamente:**
- ✅ `host_root` - Ruta al directorio home-server
- ✅ `puid` / `pgid` - IDs de usuario y grupo
- ✅ `docker_gid` - ID del grupo docker (Linux)
- ✅ `tz` - Zona horaria del sistema

**Solo necesitas añadir manualmente:**
```toml
[global]
# ⚠️ REQUERIDO: Añade tu dominio
domain = "tudominio.com"

# ⚠️ REQUERIDO: Configuración de infraestructura (obligatoria)
[infra.cloudflare]
email = "tu-email@ejemplo.com"
dns_api_token = "tu-token-cloudflare"

[infra.auth]
google_client_id = "tu-client-id.apps.googleusercontent.com"
google_client_secret = "tu-client-secret"
oauth_whitelist = "tu-email@gmail.com"
```

> **💡 Ver guía completa**: [Cómo obtener tokens de Cloudflare y OAuth](docs/installation.md#-configuración-de-infraestructura-obligatoria)

```bash
# 4. Iniciar HMS (esto levanta automáticamente infra y otros stacks habilitados)
hms start

# 5. Levantar otros stacks manualmente si es necesario (ej: media)
hms media up
```

### Primeros Comandos

```bash
# Iniciar HMS (levanta infra automáticamente + stacks habilitados)
hms start

# Ver stacks disponibles
hms list

# Ver logs de infra (sistema)
hms infra logs

# Levantar un stack adicional (ej: media)
hms media up

# Ver logs de un stack
hms media logs

# Ver información de un stack
hms media info

# Detener un stack
hms media down

# Detener HMS (detiene todos los stacks)
hms stop
```

## 📚 Documentación

- **[Guía de Instalación](docs/installation.md)** - Instalación detallada y configuración inicial
- **[Referencia de Comandos CLI](docs/cli-reference.md)** - Todos los comandos disponibles con ejemplos
- **[Documentación de Stacks](docs/stacks/)** - Guías individuales para cada stack disponible
- **[Guía de Desarrollo](docs/development/)** - Crear nuevos stacks y plugins

## 📦 Stacks Disponibles

| Stack | Descripción |
|-------|-------------|
| **media** | Gestión multimedia (Jellyfin, Radarr, Sonarr, etc.) |
| **necesse** | Servidor de juego Necesse |
| **home** | Dashboard de servicios HMS |
| **steam** | 🚧 ArchiSteamFarm (en construcción) |
| **helloworld** | Stack de ejemplo para desarrollo |

> **ℹ️ Nota**: El stack `infra` (infraestructura base con Traefik, TinyAuth, Watchtower) se levanta automáticamente con `hms start` y es obligatorio para el funcionamiento del sistema.

Más información: [Documentación de Stacks](docs/stacks/README.md)

## 🛠️ Estructura del Proyecto

```
home-server/
├── docs/                        # Documentación completa del proyecto
├── hms/                         # Código Python principal (CLI, daemon, plugins)
├── core/                        # Docker Compose configs (HMS e infraestructura)
├── stacks/                      # Stacks disponibles (media, necesse, home, steam, etc)
├── data/                        # Datos persistentes de los servicios
├── logs/                        # Logs del sistema
├── config.toml                  # Configuración (editable, necesaria)
├── config.default.toml          # Configuración por defecto
├── install.sh                   # Script de instalación
├── uninstall.sh                 # Script de desinstalación
├── update.sh                    # Script de actualización
└── pyproject.toml               # Dependencias Python
```

## 🔧 Stack Tecnológico

- **Docker Compose** - Orquestación de contenedores
- **Python 3.11+** - CLI y lógica principal
- **FastAPI** - API REST opcional
- **APScheduler** - Scheduler de tareas
- **TOML** - Formato de configuración
- **PyYAML** - Parseo de YAML para Compose


## 📄 Licencia

Este proyecto está licenciado bajo la **MIT License**.

Ver [LICENSE](LICENSE) para más detalles.

**En resumen:**
- ✅ Puedes usar, modificar y distribuir el código
- ✅ Puedes usar el código con fines comerciales
- ✅ Puedes cambiar la licencia si lo deseas
- ℹ️ Solo necesitas mantener la referencia a la licencia MIT original
