# Plan: Migración HMS a Python + Contenedor + UX Dinámica

**TL;DR:** Migrar HMS de bash a Python containerizado con:
- **UX nueva:** `hms <stack(s)> <acción>` (intuitivo, flexible)
- **Stacks dinámicos:** Autodescubiertos desde `docker/`
- **Multi-stack:** `hms up`, `hms platform,media down`
- **Acción `prep`:** Ejecutar pre-deploy manual (genera config dinámica)
- **Plugins dinámicos:** Autodescubrimiento en runtime
- **OneDrive API:** Lectura directa de credenciales (sin rclone)
- **Daemon 24/7:** Scheduler integrado (APScheduler)
- **File-based locks:** Manejo de concurrencia seguro

---

## 1. UX Pattern: `hms <stacks> <acción>`

### Sintaxis General
```bash
hms [opciones] [<stacks>] <acción> [args]

Donde:
  <stacks>   := vacío (todos) | "stack1" | "stack1,stack2,stack3"
  <acción>   := up | down | restart | status | logs | pull | prep | enable | disable
  [opciones] := --verbose, --dry-run
```

### Ejemplos de Uso

**Stack único:**
```bash
hms platform up                      # Deploy platform (prep automático)
hms media down --volumes             # Parar + eliminar volúmenes
hms home status                      # Ver estado
hms necesse logs --follow            # Ver logs en vivo
```

**Multi-stack:**
```bash
hms up                               # Deploy TODOS los habilitados
hms platform,media up                # Deploy solo estos 2
hms down --force                     # Parar TODOS (sin confirmación)
hms platform,home disable            # Deshabilitar múltiples
```

**Pre-deploy manual:**
```bash
hms platform prep                    # Ejecutar pre-deploy.sh de platform
hms prep                             # Pre-deploy de TODOS
hms media prep --force               # Forzar regeneración
```

**Global commands (sin stack):**
```bash
hms backup create                    # Backup de stacks habilitados
hms backup list                      # Listar backups
hms config onedrive-setup            # Setup OAuth (primera vez)
hms show stacks                      # Listar stacks disponibles
hms show status                      # Estado global
hms system init                      # Setup inicial (wizard)
hms system logs --lines=50           # Ver logs del sistema
```

---

## 2. Acciones de Stack (aplican a cualquier stack)

| Acción | Comportamiento | Opciones |
|--------|----------------|----------|
| **`up`** | Deploy: genera `.env` + `prep` + `docker compose up` | `--rebuild`, `--restart`, `--force` |
| **`down`** | Parar contenedores | `--volumes`, `--images`, `--networks`, `--clean`, `--force` |
| **`restart`** | Parar y reinicar | `--rebuild` |
| **`status`** | Ver estado y contenedores | `--quiet` |
| **`logs`** | Ver logs | `--lines=100`, `--follow` |
| **`pull`** | Descargar imágenes nuevas | (sin opciones) |
| **`prep`** | Ejecutar pre-deploy.sh manualmente | `--force` |
| **`enable`** | Habilitar + deploy | `--no-up`, `--rebuild` |
| **`disable`** | Deshabilitar + parar | `--no-down`, `--volumes`, `-r "razón"` |

**Nota:** `prep` ejecuta el archivo `docker/<stack>/pre-deploy.sh` si existe. Generalmente se llama automáticamente en `up`, pero puede ejecutarse manualmente para:
- Regenerar configuración dinámica (Samba en platform, GPU en media)
- Troubleshooting
- Cambios de configuración sin hacer deploy

---

## 3. Global Commands (operaciones globales)

### `backup` - Gestión de copias de seguridad
```bash
hms backup create [--stacks=X] [--force]     # Crear backup manual
hms backup list                               # Listar backups disponibles
hms backup restore <nombre-backup>            # Restaurar desde backup
hms backup schedule [status|disable|run-now]  # Gestionar automatización
```

### `config` - Configuración y credenciales
```bash
hms config onedrive-setup                     # OAuth setup (primera vez)
hms config sync --force                       # Reintentar descarga desde OneDrive
```

### `show` - Información
```bash
hms show stacks                               # Listar stacks (con descripción)
hms show status [--all]                       # Estado global de servicios
```

### `system` - Setup y logs
```bash
hms system init                               # Setup inicial (wizard interactivo)
hms system logs [--lines=50] [--follow]      # Ver logs del daemon HMS
```

---

## 4. Stacks Dinámicos (autodescubiertos)

**Descubrimiento automático:**
- Escanear carpeta `docker/` buscando directorios con `docker-compose.yml`
- Leer metadata desde `config/stacks.yml` (si existe)
- Detectar `pre-deploy.sh` en cada stack

**Stacks actuales detectados:**
- `platform` (Traefik, TinyAuth, Watchtower, Samba)
- `home` (Dashboard del servidor)
- `media` (Jellyfin, Radarr, Sonarr, qBittorrent, etc)
- `necesse`, `steam`, `zomboid`, `helloworld`
- *Cualquier stack futuro agregado en `docker/`*

**Validación:**
- Si stack no tiene `docker-compose.yml` → ignorado
- Si stack está deshabilitado en `state.yml` → no incluido en `hms up` (pero sí en `hms <stack> up --force`)

---

## 5. Arquitectura Interna: Plugins Dinámicos

**Estructura:**
```
hms/plugins/
├── stacks/                           # Acciones para cualquier stack
│   ├── __init__.py
│   ├── up.py                         # DeployUpPlugin
│   ├── down.py                       # DeployDownPlugin
│   ├── restart.py
│   ├── status.py
│   ├── logs.py
│   ├── pull.py
│   ├── prep.py                       # ← NUEVO: ejecuta pre-deploy.sh
│   ├── enable.py
│   └── disable.py
│
└── global/                           # Global commands
    ├── backup/
    │   ├── __init__.py
    │   ├── create.py
    │   ├── list.py
    │   ├── restore.py
    │   └── schedule.py
    ├── config/
    │   ├── __init__.py
    │   ├── onedrive_setup.py         # OAuth Device Flow
    │   └── sync.py                   # Forzar descarga desde OneDrive
    ├── show/
    │   ├── __init__.py
    │   ├── stacks.py
    │   └── status.py
    └── system/
        ├── __init__.py
        ├── init.py                   # Wizard setup
        └── logs.py
```

**Dispatcher (hms/core/cli.py):**
1. Parsear args buscando flags globales (`--verbose`, `--dry-run`)
2. Detectar si primer arg es stack (regex: `^[a-z0-9,]+$`) o global command
3. **Stack mode:**
   - Parsear lista de stacks (separados por coma)
   - Validar acción existe
   - Expandir stacks vacío a todos habilitados
   - Ejecutar acción para cada stack (respetando locks)
4. **Global mode:**
   - Parsear subcomando
   - Ejecutar plugin global

---

## 6. Plugin `prep` (Pre-Deploy Manual)

**Ubicación:** `hms/plugins/stacks/prep.py`

**Comportamiento:**
```python
class PrepPlugin(BasePlugin):
    def run(self, stack_name, args):
        # 1. Validar que stack existe
        # 2. Buscar docker/<stack>/pre-deploy.sh
        # 3. Si no existe → log info y retornar
        # 4. Si existe:
        #    - Cargar .env del stack
        #    - Ejecutar pre-deploy.sh
        #    - Capturar output
        #    - Validar exit code
        # 5. Logging detallado
```

**Ejemplos de pre-deploy:**
- **platform:** Genera `docker-compose.override.yml` con volúmenes Samba dinámicos
- **media:** Genera `docker-compose.override.yml` con configuración GPU (Intel QSV, NVIDIA, VAAPI)
- Otros stacks: Si no tienen `pre-deploy.sh` → no hace nada

---

## 7. Detección Dinámica de Stacks

**En `hms/lib/stacks.py`:**
```python
def discover_stacks() -> list[str]:
    """Descubre stacks escaneando docker/"""
    stacks = []
    docker_dir = Path(PROJECT_ROOT) / "docker"
    
    if docker_dir.exists():
        stacks = [
            d.name for d in docker_dir.iterdir() 
            if d.is_dir() and (d / "docker-compose.yml").exists()
        ]
    
    return sorted(stacks)

def get_stack_info(stack_name: str) -> dict:
    """Lee metadata del stack (description, config_files, services)"""
    # Leer desde config/stacks.yml si existe
    # Fallback a valores por defecto si no está en config
    pass

def has_predeploy(stack_name: str) -> bool:
    """Verifica si stack tiene pre-deploy.sh"""
    return (Path(PROJECT_ROOT) / "docker" / stack_name / "pre-deploy.sh").exists()
```

---

## 8. Flujo de `hms up` (con prep automático)

```
hms platform up
│
├─ 1. Descubrir stacks → [platform, home, media, ...]
├─ 2. Validar que "platform" existe
├─ 3. Validar que no hay otro deploy en progreso (check locks)
├─ 4. Adquirir lock: /data/locks/platform.lock
├─ 5. Cargar .env desde OneDrive (cache o API)
├─ 6. Ejecutar pre-deploy.sh (equiv a `hms platform prep`)
│   └─ Genera docker-compose.override.yml con config dinámica
├─ 7. docker compose -f docker/platform/docker-compose.yml up -d
├─ 8. Esperar health checks
├─ 9. Actualizar state.yml
├─ 10. Liberar lock
└─ 11. Output: ✅ Platform deployed successfully

```

---

## 9. Arquitectura de Credenciales: OneDrive API

**Estructura en OneDrive:**
```
/HMS/config/
  ├── cloudflare.env
  ├── auth.env
  ├── common.env
  ├── media.env
  ├── samba.env
  └── watchtower.env
```

**Flujo de lectura en Python:**
```python
# En hms/lib/config.py
def load_env_for_stack(stack_name: str) -> dict:
    # 1. Check cache local en /data/hms-config/cache/{stack_name}.env
    # 2. Si cache válido (< 1 hora) → retornar
    # 3. Si no:
    #    - Conectar a OneDrive vía Microsoft Graph API
    #    - Descargar /{stack_name}.env
    #    - Guardar en cache
    #    - Parsear y retornar
    # 4. Si falla OneDrive:
    #    - Si hay cache local → usar (offline mode)
    #    - Si no hay cache → error
```

**OAuth Setup (primera vez):**
```bash
hms config onedrive-setup
```

**Flujo:**
1. Mostrar Device Code en terminal
2. Usuario abre navegador y autoriza app
3. Guardar tokens en `/data/hms-config/tokens.json`
4. Renovación automática por msgraph-sdk

---

## 10. Sistema de Locks (Concurrencia)

**Ubicación:** `/data/locks/{stack}.lock`

**Formato del lock:**
```
timestamp|pid|operation
ejemplo: 1705681200|12345|deploy
```

**Uso:**
```python
# En hms/lib/locks.py
with acquire_stack_lock("platform", timeout=900):  # 15 minutos
    # Operación crítica
    deploy_stack("platform")
    # Lock se libera automáticamente
```

**Comportamiento:**
- CLI falla rápido si hay lock: `⏳ Stack 'platform' bloqueado por deploy (hace 2m)`
- Scheduler respeta locks: pospone automáticamente
- Limpieza de locks expirados en startup

---

## 11. Daemon 24/7 con APScheduler

**Jobs automáticos:**
- **OneDrive sync:** cada 1 hora (refrescar cache `.env`)
- **DNS sync:** cada 30 min (si aplica)
- **Mantenimiento:** diario 2:00 AM (limpieza)
- **Backup:** semanal domingo 3:00 AM
- **Health checks:** cada 5 min

**Respeta locks:** antes de ejecutar job, intenta adquirir lock; si falla, pospone automáticamente

**Persistencia:** SQLite en `/data/scheduler.db`

---

## 12. Logging

**Archivo:** `/data/logs/hms.log`

**Niveles:** DEBUG, INFO, WARNING, ERROR

**Rotación:** diaria, retención 7 días

**Contenido:**
```
[2025-01-19 14:35:22] INFO   🚀 Starting deploy of platform
[2025-01-19 14:35:23] INFO   📝 Loading .env from cache
[2025-01-19 14:35:24] INFO   🔧 Running pre-deploy.sh
[2025-01-19 14:35:25] INFO   ✅ docker compose up -d
[2025-01-19 14:35:35] INFO   ✅ Platform deployed successfully (duration: 13s)
```

---

## 13. Mapeo: Comandos Bash Antiguos → Nueva UX

| Old | New |
|-----|-----|
| `commands/deploy/up platform` | `hms platform up` |
| `commands/deploy/down media --volumes` | `hms media down --volumes` |
| `commands/deploy/enable platform` | `hms platform enable` |
| `commands/deploy/disable media` | `hms media disable` |
| `commands/backup/create` | `hms backup create` |
| `commands/backup/list` | `hms backup list` |
| `commands/info` | `hms show stacks` |
| `commands/status` | `hms show status` |
| (N/A) | `hms platform prep` ← NUEVO |

---

## 14. Fases de Implementación

### Fase 1 (3-4 semanas): MVP funcional
- Core: Dispatcher + plugin system
- Acciones de stack: up, down, restart, status, logs, pull, prep, enable, disable
- Global commands: backup (create, list, restore), show (stacks, status), system (init, logs)
- Soporte local de .env (fallback antes de OneDrive)
- Docker + docker-compose básico
- **Testing:** Sin OneDrive aún

### Fase 2 (2-3 semanas): OneDrive Integration
- Implementar `hms/lib/onedrive.py`
- Plugin `config/onedrive-setup.py`
- Plugin `config/sync.py`
- Cache system con TTL
- **Testing:** Lectura/cache de .env desde OneDrive

### Fase 3 (2 semanas): Daemon + Scheduler
- APScheduler completo
- Jobs periódicos
- Health checks
- Structured logging
- **Testing:** Concurrencia con locks

### Fase 4 (1-2 semanas): Pulido
- Documentación completa
- Manejo de errores mejorado
- Tests automatizados
- Performance optimization

---

## 15. Docker Compose para HMS

```yaml
version: '3.8'

services:
  hms:
    build:
      context: .
      dockerfile: docker/hms/Dockerfile
    container_name: hms-container
    restart: always
    environment:
      HMS_MODE: daemon
      HMS_LOCK_TIMEOUT: "900"
      HMS_ONEDRIVE_ENABLED: "true"
      HMS_CONFIG_DIR: /app/data/hms-config
      PROJECT_ROOT: /project
      PYTHONUNBUFFERED: "1"
    volumes:
      - .:/project:ro
      - ./data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - proxy
    healthcheck:
      test: ["CMD", "python", "-m", "hms.cli", "show", "status", "--quiet"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  proxy:
    external: true
```

---

## 16. CLI desde Host (Wrapper)

```bash
#!/bin/bash
# /usr/local/bin/hms
docker exec -it hms-container python -m hms.cli "$@"
```

O alias en `~/.zshrc`:
```bash
alias hms='docker exec -it hms-container python -m hms.cli'
```

---

## Resumen de Cambios Principales

| Aspecto | Antes (Bash) | Después (Python) |
|---------|--------------|------------------|
| **UX** | `hms deploy up platform` | `hms platform up` |
| **Stacks** | Hardcoded en scripts | Dinámicos desde `docker/` |
| **Multi-stack** | `for stack in...` loops | `hms platform,media up` |
| **Pre-deploy** | Invisible, solo en `up` | Visible: `hms platform prep` |
| **Credenciales** | rclone mount + symlinks | OneDrive API + cache |
| **Scheduler** | cron | APScheduler (daemon) |
| **CLI remota** | `ssh user@host ./scripts/...` | `docker exec -it hms-container hms ...` |
| **Logs** | Múltiples archivos | Centralizado: `/data/logs/hms.log` |

---

## Decisiones Técnicas Finales

✅ **Plugin system dinámico** → Extensible, fácil agregar comandos  
✅ **OneDrive API directo** → Sin rclone, sin montar filesystem  
✅ **File-based locks** → Robusto, simple, sin deps externas  
✅ **Daemon 24/7 + APScheduler** → Reemplaza cron, más flexible  
✅ **Stacks autodescubiertos** → Cero configuración para stacks nuevos  
✅ **UX `hms <stack> <acción>`** → Intuitivo, menos typing  
✅ **`prep` visible** → Control manual sobre pre-deploy  

---

## Próximos Pasos Inmediatos

1. ✅ Confirmación de UX y naming (COMPLETADO)
2. → Crear estructura base: `hms/`, `hms/core/`, `hms/plugins/`, `hms/lib/`
3. → Implementar `BasePlugin` + dispatcher
4. → Migrar primer plugin: `show/stacks.py`
5. → Crear Dockerfile + docker-compose
6. → Probar end-to-end: `hms show stacks`

---

**Estado:** Plan final confirmado y documentado ✅

