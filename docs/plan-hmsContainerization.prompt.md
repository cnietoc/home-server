## Plan: Migración HMS a Python + Contenedor con Plugins Dynamic + OneDrive API

**TL;DR:** Migrar sistema HMS de bash a Python containerizado. Contenedor único 24/7 con CLI remota (`docker exec`), sistema de **plugins dinámicos** (autodescubrimiento), **lectura directa de credenciales desde OneDrive vía Microsoft Graph API** (sin rclone, sin montar filesystem), **state local**, **file-based locks** para concurrencia, y scheduler integrado (APScheduler). Tokens OAuth en carpeta local no versionada.

### Steps

1. **Diseñar sistema de plugins dinámicos (replicando `resolve_command` bash)**
   - Dispatcher Python en `hms/core/cli.py` que descubre plugins automáticamente escaneando `hms/plugins/`.
   - Cada plugin: clase heredando `BasePlugin` con métodos `run(args)`, `get_help()`, `get_description()`.
   - Estructura: `hms/plugins/{category}/{command}.py` (ej: `hms/plugins/deploy/up.py`).
   - Carga dinámica en runtime: importar solo cuando se ejecuta (lazy loading).
   - Soportar jerarquías: `hms/plugins/deploy/index.py` como help de categoría.
   - Preserva UX: `hms deploy up platform` → descubre y ejecuta `plugins/deploy/up.py`.

2. **Arquitectura de credenciales: OneDrive API + cache local**
   - **Lectura directa desde OneDrive:**
     - Usar **Microsoft Graph API** (vía `msgraph-sdk-python`) para leer archivos `.env` directamente.
     - Ruta OneDrive: `/HMS/config/` (contiene `cloudflare.env`, `auth.env`, `common.env`, etc).
     - Python descarga archivos bajo demanda al iniciar o cuando se necesiten.
   - **Configuración HMS (no versionada):**
     - Nueva carpeta: `/data/hms-config/` (en `.gitignore`).
     - Contenido:
       - `tokens.json` → OAuth tokens (access + refresh token).
       - `onedrive.json` → metadata (file IDs, last sync timestamp).
       - `cache/` → archivos `.env` cacheados localmente (opcional, para offline).
   - **Flujo de lectura:**
     1. Python verifica si hay cache válido en `/data/hms-config/cache/*.env`.
     2. Si no hay cache o expiró (>1 hora): descarga desde OneDrive vía API.
     3. Guarda en cache para próximas lecturas.
     4. Parsea `.env` y carga en memoria.
   - **Ventaja:** Sin rclone, sin montar OneDrive, sin symlinks. Acceso directo vía API.

3. **OAuth Device Flow para OneDrive (setup inicial)**
   - Comando: `hms config onedrive-setup` (interactivo, primera vez).
   - Flujo:
     1. Mostrar Device Code en terminal.
     2. Usuario abre navegador → authoriza app.
     3. Python recibe tokens (access + refresh).
     4. Guardar en `/data/hms-config/tokens.json`.
     5. Renovación automática: librería `msgraph-sdk-python` renueva tokens expirados automáticamente.
   - Permisos requeridos: `Files.Read.All` (solo lectura).

4. **Estructura de datos locales: state + locks + config HMS**
   - **State:** `/data/state.yml` (historial deployments, timestamps, hashes).
   - **Locks:** `/data/locks/{stack}.lock` (formato: `timestamp|pid|operation`).
   - **Scheduler DB:** `/data/scheduler.db` (SQLite para APScheduler).
   - **Logs:** `/data/logs/hms.log` (rotación diaria, retención 7 días).
   - **Config HMS (NUEVO):** `/data/hms-config/`
     - `tokens.json` → OAuth tokens OneDrive.
     - `onedrive.json` → metadata (file IDs, sync status).
     - `cache/` → archivos `.env` cacheados.
   - Todo en `.gitignore` excepto estructura de directorios.

5. **Sistema de locks file-based para manejo de concurrencia**
   - Librería `filelock` (PyPI) con wrapper en `hms/lib/locks.py`.
   - Antes de operación (CLI o Scheduler): adquirir lock con timeout 15 min.
   - Lock file contiene: `{timestamp}|{pid}|{operation}` para debugging.
   - CLI falla rápido si hay lock: `⏳ Stack 'platform' bloqueado por deploy (hace 2m)`.
   - Scheduler respeta locks: detecta lock → pospone tarea automáticamente.
   - Limpieza automática: locks expirados >15min se liberan con warning en logs.

6. **Arquitectura de contenedor HMS único**
   - Base image: `python:3.12-slim`.
   - Dependencies (requirements.txt):
     ```
     pyyaml>=6.0
     docker>=7.0
     click>=8.1
     apscheduler>=3.10
     aiofiles>=23.0
     filelock>=3.13
     python-dotenv>=1.0
     msgraph-sdk>=1.0
     azure-identity>=1.15
     requests>=2.31
     ```
   - Volúmenes Docker:
     - `.:/project:ro` → código y configuración (read-only).
     - `./data:/app/data` → datos persistentes (logs, state, locks, **hms-config**).
     - `/var/run/docker.sock:/var/run/docker.sock:ro` → control Docker host.
   - ENTRYPOINT: `python -m hms.main` (detecta modo: daemon vs cli).
   - Env vars:
     - `HMS_MODE=daemon|cli`
     - `HMS_LOCK_TIMEOUT=900`
     - `HMS_ONEDRIVE_ENABLED=true` (habilitar lectura OneDrive)
     - `HMS_CONFIG_DIR=/app/data/hms-config`
     - `PROJECT_ROOT=/project`
   - Healthcheck: verificar Docker daemon + scheduler activo cada 30s.

7. **Módulos Python: estructura completa con plugins + OneDrive**
   ```
   hms/
     __main__.py              # Entry point principal
     main.py                  # Lógica de inicio (daemon/cli mode)
     __init__.py
     
     core/
       cli.py                 # Dispatcher + plugin loader dinámico
       plugin.py              # BasePlugin abstract class
       
     plugins/                 # Autodescubibles (estructura mirrors bash commands/)
       deploy/
         __init__.py
         index.py             # Help de categoría
         up.py                # DeployUpPlugin
         down.py
         enable.py
         disable.py
       backup/
         __init__.py
         create.py
         restore.py
         list.py
       config/
         __init__.py
         generate.py
         validate.py
         onedrive_setup.py    # NUEVO: OAuth setup interactivo
         sync.py              # NUEVO: forzar sync desde OneDrive
       setup/
         __init__.py
         init.py
         docker.py
       maintain/
         __init__.py
         clean.py
         update.py
       show/
         __init__.py
         stacks.py
         status.py
         
     daemon/
       main.py                # Event loop del daemon
       scheduler.py           # APScheduler + jobs configuration
       
     lib/
       logs.py                # Logger con rotación diaria
       docker.py              # Docker SDK wrapper
       config.py              # Config loader (.env + YAML)
       state.py               # State management con atomic writes
       stack.py               # Stack YAML parsing
       utils.py               # Utilidades generales
       locks.py               # File-based locking
       onedrive.py            # NUEVO: Microsoft Graph API client
       
     tests/
       test_plugins.py
       test_locks.py
       test_state.py
       test_onedrive.py
   ```

8. **Implementación de `hms/lib/onedrive.py` (módulo crítico)**
   ```python
   """
   OneDrive client usando Microsoft Graph API.
   
   Funcionalidades:
   - OAuth Device Flow (primera vez)
   - Descarga de archivos .env desde OneDrive
   - Cache local con TTL
   - Renovación automática de tokens
   """
   
   import json
   from pathlib import Path
   from datetime import datetime, timedelta
   from msgraph import GraphServiceClient
   from azure.identity import DeviceCodeCredential
   
   class OneDriveClient:
       def __init__(self, config_dir: Path):
           self.config_dir = config_dir
           self.tokens_file = config_dir / "tokens.json"
           self.metadata_file = config_dir / "onedrive.json"
           self.cache_dir = config_dir / "cache"
           self.cache_ttl = timedelta(hours=1)
           
       def authenticate(self):
           """OAuth Device Flow (interactivo)"""
           # Implementar Device Code Flow
           
       def download_env_file(self, filename: str) -> str:
           """Descarga archivo .env desde OneDrive"""
           # 1. Check cache
           # 2. Si no existe o expiró, descargar desde OneDrive
           # 3. Guardar en cache
           # 4. Retornar contenido
           
       def list_env_files(self) -> list[str]:
           """Lista todos los .env en OneDrive/HMS/config/"""
           
       def get_cached_env(self, filename: str) -> str | None:
           """Lee .env desde cache local si existe y es válido"""
   ```

9. **CLI del host: wrapper bash mínimo**
   - Reemplazar script `/hms` actual:
     ```bash
     #!/bin/bash
     set -euo pipefail
     # Wrapper para contenedor HMS
     docker exec -it hms-container python -m hms.cli "$@"
     ```
   - Alias alternativo en `~/.zshrc`: `alias hms='docker exec -it hms-container python -m hms.cli'`.
   - Señales: `docker exec -it` propaga Ctrl+C automáticamente.
   - UX idéntica: `hms deploy up platform`, `hms backup create`, etc.

10. **Scheduler integrado: demonios periódicos 24/7**
    - APScheduler con backend SQLite (`/app/data/scheduler.db`).
    - Jobs configurados:
      - **OneDrive sync:** cada 1 hora (refrescar cache de .env).
      - **DNS sync:** cada 30 min (update-dns).
      - **Mantenimiento diario:** 2:00 AM (sin backup, solo limpieza).
      - **Backup semanal:** Domingo 3:00 AM (backup completo + limpieza).
      - **Health check:** cada 5 min (verificar contenedores).
    - Respeta locks: antes de ejecutar job, intenta adquirir lock; si falla, pospone.
    - Logs compartidos: mismo archivo que CLI (`/data/logs/hms.log`).
    - Persistencia: jobs sobreviven restart del contenedor.

11. **Docker Compose para HMS**
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
          test: ["CMD", "python", "-m", "hms.cli", "info", "status", "--quiet"]
          interval: 30s
          timeout: 10s
          retries: 3
          
    networks:
      proxy:
        external: true
    ```

12. **Fases de implementación (MVP-first approach)**
    
    **Fase 1 (3 semanas) - MVP funcional SIN OneDrive:**
    - Core: Dispatcher + plugin system + BasePlugin.
    - Librerías base: logs, docker, config (lee .env locales), state, locks.
    - Plugins críticos:
      - `deploy/up.py`, `deploy/down.py`
      - `backup/create.py`, `backup/list.py`, `backup/restore.py`
      - `config/generate.py`, `config/validate.py`
      - `show/stacks.py`, `show/status.py`
    - Dockerfile + docker-compose básico.
    - CLI wrapper bash.
    - **Testing:** Usar archivos `.env` locales (ej: `/config/private` actual como fallback).
    
    **Fase 2 (2 semanas) - Integración OneDrive:**
    - Implementar `hms/lib/onedrive.py` (Microsoft Graph API).
    - Plugin `config/onedrive_setup.py` (OAuth Device Flow).
    - Plugin `config/sync.py` (forzar descarga desde OneDrive).
    - Sistema de cache con TTL.
    - Job scheduler: sync OneDrive cada 1 hora.
    - **Testing:** Verificar lectura/cache de `.env` desde OneDrive.
    
    **Fase 3 (2 semanas) - Scheduler + automatización:**
    - Daemon mode + APScheduler completo.
    - Jobs periódicos: DNS, mantenimiento, backups.
    - Health checks.
    - Logging mejorado (structured logs).
    - Testing de concurrencia (locks).
    
    **Fase 4 (1-2 semanas) - Setup completo:**
    - Plugin `setup/init.py` (wizard interactivo).
    - Migración completa de comandos restantes.
    - Comandos system: `setup/docker`, `setup/networks`, `maintain/clean`.
    - Documentación completa.
    
    **Fase 5 (ongoing) - Refinamiento:**
    - Tests automatizados (pytest).
    - CI/CD integration.
    - Plugins adicionales según necesidad.
    - Optimizaciones de performance.
    - UI web (opcional, muy futuro).

### Decisiones Técnicas Finales

| Aspecto | Decisión | Justificación |
|---------|----------|---------------|
| **State** | Local en `/data/state.yml` | Mejor rendimiento, no necesita sync |
| **Credenciales** | OneDrive vía Microsoft Graph API | Sin rclone, sin montar, acceso directo |
| **Tokens OAuth** | Local en `/data/hms-config/tokens.json` | No versionado, renovación automática |
| **Cache .env** | Local en `/data/hms-config/cache/` con TTL 1h | Performance + offline support |
| **Contenedor** | Único HMS (no múltiples) | Simplicidad, menos overhead |
| **Plugin system** | Dinámico con autodescubrimiento | Extensible, fácil agregar comandos |
| **Locks** | File-based con timeout | Simple, robusto, sin deps externas |
| **CLI remota** | `docker exec` desde host | Transparent, preserva UX |
| **Scheduler** | APScheduler integrado | Reemplaza cron, más flexible |
| **Estructura** | Mirrors bash actual | Facilita migración incremental |

### Further Considerations

1. **OneDrive: Estructura de archivos en la nube**
   - Ruta esperada en OneDrive: `/HMS/config/`
   - Archivos:
     - `cloudflare.env`
     - `auth.env`
     - `common.env`
     - `media.env`
     - `samba.env`
     - `watchtower.env`
   - Python lista archivos `.env` y los descarga bajo demanda.

2. **Fallback si OneDrive no disponible:**
   - Si falla autenticación o red: usar cache local si existe.
   - Si no hay cache: fallar con error claro → `⚠️ No se pudo acceder a OneDrive y no hay cache local`.
   - Comando manual: `hms config sync --force` para reintentar descarga.

3. **Seguridad de tokens:**
   - `tokens.json` con permisos 600 (solo lectura por owner).
   - Considerar cifrado futuro (Fase 5).
   - Rotación automática de tokens por msgraph-sdk.

4. **Migración de scripts bash a plugins Python:**
   - Mantener scripts bash originales en `scripts/` como fallback durante migración.
   - Cada plugin nuevo marca comando como "migrado" en tracking interno.
   - Deprecar bash scripts gradualmente (warnings primero, eliminar después).

5. **Compatibilidad durante transición:**
   - CLI wrapper puede detectar si comando existe en Python; si no, fallback a bash.
   - Permite migración incremental sin romper funcionalidad existente.

6. **Testing strategy:**
   - Unit tests para librerías core (locks, state, config, onedrive).
   - Integration tests para plugins (mock Docker, mock OneDrive API).
   - End-to-end tests manuales para operaciones críticas (deploy, backup).

7. **Manejo de errores y rollback:**
   - State snapshots antes de operaciones críticas.
   - Comando `hms state rollback <timestamp>` para revertir.
   - Logs detallados para debugging (nivel configurable: DEBUG, INFO, ERROR).

8. **Performance considerations:**
   - Lazy loading de plugins (importar solo cuando ejecuta).
   - Cache de parsing YAML (stacks.yml, state.yml).
   - Cache de .env desde OneDrive (TTL 1 hora).
   - Async operations donde aplique (backups, health checks, OneDrive downloads).

### Próximos Pasos Inmediatos

1. Crear estructura de directorios Python (`hms/`, `hms/core/`, `hms/plugins/`).
2. Implementar `BasePlugin` y dispatcher básico.
3. Migrar primer plugin: `show/stacks.py` (read-only, bajo riesgo).
4. Crear Dockerfile básico + docker-compose.
5. Probar end-to-end: `hms show stacks` funcionando desde contenedor (sin OneDrive).
6. **Fase 2:** Implementar `hms/lib/onedrive.py` + OAuth setup.

---

**Estado actual:** Planificación completa ✅  
**Siguiente acción:** Iniciar Fase 1 - crear estructura básica Python (sin OneDrive)

---

**Arquitectura OneDrive explicada:**

```
┌─────────────────────────────────────────────────────────────┐
│                    OneDrive Cloud                           │
│  📁 /HMS/config/                                            │
│    ├── cloudflare.env                                       │
│    ├── auth.env                                             │
│    ├── common.env                                           │
│    └── media.env                                            │
└─────────────────────────────────────────────────────────────┘
                         ▲
                         │ Microsoft Graph API
                         │ (msgraph-sdk-python)
                         │
┌────────────────────────┴────────────────────────────────────┐
│              HMS Container (Python)                         │
│  📦 hms/lib/onedrive.py                                     │
│    - OAuth Device Flow                                      │
│    - Download .env files                                    │
│    - Cache management                                       │
│                                                             │
│  📁 /app/data/hms-config/                                  │
│    ├── tokens.json        (OAuth tokens)                   │
│    ├── onedrive.json      (metadata)                       │
│    └── cache/                                              │
│        ├── cloudflare.env  (cached, TTL 1h)               │
│        ├── auth.env                                        │
│        └── common.env                                      │
└─────────────────────────────────────────────────────────────┘
```

**Ventajas de esta arquitectura:**
✅ Sin rclone (una dependencia menos)  
✅ Sin montar filesystem OneDrive  
✅ Sin symlinks complejos  
✅ Acceso directo vía API REST  
✅ Cache local para performance + offline  
✅ Renovación automática de tokens  
✅ Credenciales en OneDrive = backup automático

