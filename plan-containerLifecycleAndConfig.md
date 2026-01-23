# Plan: Refactorizar gestión de contenedor y configuración

**Fecha**: 2026-01-23  
**Objetivo**: Simplificar `install.sh`, crear comandos bash puros para arrancar/parar contenedor, y migrar PUID/PGID/TZ
a `config.toml`.

---

## Resumen Ejecutivo

- **Simplificar `install.sh`**: Solo crear symlink, no levantar contenedor ni generar `.env`.
- **Comandos bash puros**: `hms start/stop` (ejecutados en host, no dentro del contenedor).
- **Migrar config**: PUID/PGID/TZ de `.env` dinámico a `config.toml` que el contenedor lee al iniciar.
- **Entrypoint inteligente**: Script bash en el contenedor que parsea `config.toml` y configura variables de entorno.

---

## 1. Simplificar `install.sh`

### Cambios

- ❌ Eliminar: generación de `.env` (PUID/PGID/TZ)
- ❌ Eliminar: `docker compose up -d --build`
- ❌ Eliminar: `chown -R` de directorios
- ❌ Eliminar: prueba de CLI dentro del contenedor
- ✅ Mantener: validación de Docker, crear symlink, verificar PATH
- ✅ Agregar: generar `config.toml` inicial si no existe (vacío)

### Flujo nuevo

```bash
./install.sh
├─ Validar Docker disponible
├─ Validar docker-compose.yml existe
├─ Validar wrapper fuente existe
├─ Crear ~/.local/bin
├─ Crear/verificar symlink
├─ Verificar ~/.local/bin en PATH
├─ Validar permisos Docker (grupo en Linux)
├─ Crear config.toml inicial (si no existe)
└─ Output: "Ahora ejecuta: hms start"
```

---

## 2. Crear comandos `hms start/stop` (bash puros)

### Ubicación

```
hms/bin/commands/
├─ start    # Script bash puro
└─ stop     # Script bash puro
```

### Características

- ✅ Ejecutables desde host (sin Docker)
- ✅ Bash puro (sin Python, sin dependencias externas)
- ✅ Se invocan vía dispatcher: `hms start/stop`
- ✅ Pueden ser llamados desde el wrapper antes de iniciar contenedor

---

## 3. Modificar wrapper `/hms/bin/hms`

### Cambios

- Detectar si comando es `start/stop` → flujo especial
- Para otros comandos: verificar si contenedor corre, si no fallar y avisar
- Cambiar requisito `.env` → requisito `config.toml`

### Flujo nuevo

Vamos a tener flujos diferentes según sea start/stop u otros comandos:

#### `start`

```bash
hms start [args]
├─ Levantar el contenedor si no está corriendo
├─ Ejectuar `hms start` dentro del contenedor
│  ├ Si es primera ejecución o falta algún valor requerido, se lanza un proceso interactivo para completar config.toml con los valores requeridos.
│  └ Levanta todos los servicios internamente
└─ Output: "✅ HMS iniciado"
```

#### `stop`

```bash
hms stop
├─ Ejecutar `hms stop` dentro del contenedor para parar servicios internamente
└─ Parar el contenedor Docker
```

#### Otros comandos

```bash
hms <command> 
├─ Validar existencia de `config.toml`
│  ├─ No → fallo con mensaje: "Por favor, ejecuta scripts de instalación primero."
│  └─ Sí → continuar
└─ docker exec hms python -m hms <command>
```

---

## 4. Migrar config a `config.toml`

### Estructura nueva

```toml
[global]
domain = "__REQUIRED__"
puid = 1000          # ID del usuario del host
pgid = 1000          # ID del grupo del host
tz = "Europe/Madrid" # Timezone del sistema

[infra]
cloudflare_email = "__REQUIRED__"
cloudflare_dns_api_token = "__REQUIRED__"
```

### Detección automática

En `install.sh`, si `config.toml` no existe se genera automáticamente y si existe se actualizan `puid`, `pgid`, `tz`:

```bash
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Detectar timezone (como ya hace)
if [ -f /etc/timezone ]; then
    SYSTEM_TZ=$(cat /etc/timezone)
elif [ -L /etc/localtime ]; then
    SYSTEM_TZ=$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')
else
    SYSTEM_TZ="UTC"
fi

# Generar config.toml inicial o actualizar valores
```

---

## 5. Entrypoint del contenedor (bash)

### Script `core/hms/entrypoint.sh`

```bash
#!/usr/bin/env bash
# Entrypoint del contenedor HMS
# Lee config.toml y configura variables de entorno

set -euo pipefail

CONFIG_FILE="/app/config.toml"

# Función para parsear TOML simple (bash puro)
get_toml_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    
    grep "^\[$section\]" "$file" -A 100 | \
    grep "^$key" | \
    cut -d'=' -f2 | \
    tr -d ' "' | \
    head -1
}

# Leer valores de config.toml
if [ -f "$CONFIG_FILE" ]; then
    PUID=$(get_toml_value "$CONFIG_FILE" "global" "puid")
    PGID=$(get_toml_value "$CONFIG_FILE" "global" "pgid")
    TZ=$(get_toml_value "$CONFIG_FILE" "global" "tz")
fi 

#Falla el arranque si no existe config.toml o no se pueden leer valores
if [ -z "$PUID" ] || [ -z "$PGID" ] || [ -z "$TZ" ]; then
    echo "Error: config.toml no encontrado en $CONFIG_FILE"
    exit 1
fi

# Exportar variables para que subprocesos las hereden
export PUID PGID TZ
export TZ="$TZ"

# Crear usuario/grupo si no existen
groupadd -o -g "$PGID" -r hms 2>/dev/null || true
useradd -o -u "$PUID" -g "$PGID" -r hms 2>/dev/null || true

# Ajustar permisos de directorios
chown -R "$PUID:$PGID" /app 2>/dev/null || true

# Ejecutar comando
exec "$@"
```

### Dockerfile

Cambiar CMD/ENTRYPOINT:

```dockerfile
FROM python:3.12-slim

# ... instalaciones existentes ...

COPY core/hms/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "hms.daemon"]
```

---

## 6. Actualizar `docker-compose.yml`

### Cambios

```yaml
name: home-server
services:
  cli:
    build:
      context: ../..
      dockerfile: core/hms/Dockerfile
    container_name: hms
    restart: unless-stopped
    # ❌ Eliminar: user: "${PUID}:${PGID}"
    # ❌ Eliminar: environment.TZ
    # ✅ El entrypoint ahora maneja PUID/PGID/TZ desde config.toml
    group_add:
      - "0"
    volumes:
      - ../../config.default.toml:/app/config.default.toml:ro
      - ../../config.toml:/app/config.toml
      - ../../docker:/app/docker
      - ../../data:/app/data
      - ../../logs:/app/logs
      - /var/run/docker.sock:/var/run/docker.sock
    labels:
      com.centurylinklabs.watchtower.enable: "false"
```

---

## 7. Orden de ejecución esperado

### Primer arranque

```bash
# 1. Descargar repo
git clone ...
cd home-server

# 2. Instalar (solo symlink + config inicial)
./install.sh
# Output: "✅ Symlink creado, config.toml básico generado."
# Output: "Siguiente: hms start"

# 3. Arrancar contenedor e inicializa la configuración interactivamente
hms start
# Pide: todos los valores requeridos
# Genera: config.toml completo
# Output: "✅ HMS iniciado"

# 5. Usar normalmente
hms list
hms home up
```

### Arranques posteriores

```bash
# El wrapper detecta automáticamente:
hms list
├─ ¿Contenedor corre?
│  └─ No → fallar con mensaje
└─ Ejecuta comando dentro
```

## 10. Puntos de integración existentes

### Búsqueda de impacto

- ✅ CLI dispatcher (`hms/cli/cli.py`): agregar plugin `start` y `stop`
- ✅ Wrapper (`hms/bin/hms`): detectar comandos especiales
- ✅ Docker compose (`core/hms/docker-compose.yml`): remover PUID/PGID/TZ
- ✅ Dockerfile (`core/hms/Dockerfile`): agregar entrypoint
- ❌ `install.sh`: casi todo se reescribe
- ❌ `.env`: se elimina, sustituido por `config.toml`

### Archivos que NO cambian

- `scripts/` (bash helpers) — mantienen su función
- `hms/lib/` (librerías Python) — no afectadas
- `commands/` (plugins antiguos) — estructura se mantiene, deprecado
- Stacks y configuraciones de aplicaciones — sin cambios

---

## 11. Preguntas pendientes / Decisiones de diseño

### ¿Parsear TOML en bash o usar `yq`?

Añadimos yq como dependencia del contenedor para el entrypoint.sh, ya que es ligero y facilita el parseo. Pero para los
scripts que se ejecutan en el host, mantenemos bash puro para evitar dependencias adicionales.


