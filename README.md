# Home Server Setup

## 🚀 Stack Hello World + Traefik + Cloudflare DNS

Este proyecto configura un servidor doméstico con:
- **Traefik** como proxy inverso con SSL automático
- **TinyAuth** para autenticación centralizada con Google OAuth
- **Watchtower** para actualizaciones automáticas de imágenes Docker
- **Cloudflare DNS Challenge** para certificados Let's Encrypt
- **Dashboard dinámico** con información del servidor en tiempo real
- **Stack de medios** (Jellyfin, Radarr, Sonarr, etc.)
- **Hello World** como aplicación de prueba
- **Gestión centralizada de configuración y variables de entorno**

## 📁 Estructura del Proyecto

```
home-server/
├── config/
│   ├── templates/           # Plantillas de configuración
│   └── private -> /ruta/config  # Enlace a tu configuración (crear)
├── stacks/                 # Stacks de aplicación
│   ├── home/               # Dashboard del Home Server
│   │   ├── docker-compose.yml
│   │   └── stack.yml       # Metadata del stack
│   ├── media/              # Suite de medios (Jellyfin, Radarr, Sonarr, etc.)
│   │   ├── docker-compose.yml
│   │   └── stack.yml
│   ├── helloworld/         # Stack de prueba
│   └── ...
├── core/                   # Componentes core del sistema
│   ├── hms/                # Contenedor del CLI HMS
│   │   ├── docker-compose.yml
│   │   └── Dockerfile
│   └── infra/              # Infraestructura base (Traefik, TinyAuth, Watchtower, Samba)
│       ├── docker-compose.yml
│       └── stack.yml
├── hms/                    # CLI Python
│   ├── cli/
│   ├── commands/
│   ├── lib/
│   └── plugins/
├── scripts/                # Scripts de automatización
│   ├── deploy.sh           # Script principal de despliegue
│   ├── install-docker.sh   # Instalación de Docker (Ubuntu)
│   ├── link.sh             # Script para enlaces (config/backups)
│   ├── backup.sh           # Script para crear backups automáticos
│   ├── onedrive-manager.sh # Gestión completa de OneDrive con rclone
│   ├── setup-security.sh   # Configuración de seguridad del servidor
│   ├── setup-ssh.sh        # Configuración SSH con claves de GitHub
│   ├── update-dns.sh       # Actualización automática de DNS Cloudflare
│   └── auto-maintenance.sh # Mantenimiento automático programado
└── data/                   # Datos persistentes (volúmenes Docker)
    ├── media/              # Biblioteca multimedia y descargas
    └── backups -> /ruta/backups  # Enlace a tu directorio de backups (crear)
```

## ⚙️ Configuración Inicial

### 1. Configurar carpeta de entorno

Crea una carpeta fuera del repositorio para almacenar tus archivos de configuración de entorno (API keys, contraseñas, etc.) y enlázala al proyecto. En el caso de que no existan previamente el script los creará automáticamente a partir de las plantillas.

```bash
# Crear carpeta de configuración donde quieras (fuera del repo)
mkdir -p ~/config/home-server

# Enlazar la carpeta de configuración
./scripts/link.sh config ~/config/home-server
```

### 2. Instalar y configurar OneDrive (opcional)

Si necesitas sincronizar archivos con OneDrive, puedes instalar y configurar rclone para montarlo automáticamente:

```bash
# Instalar rclone y configurar OneDrive
./scripts/onedrive-manager.sh

# Diagnosticar problemas del servicio
./scripts/onedrive-manager.sh diagnose

# Reparar configuración si hay problemas
./scripts/onedrive-manager.sh repair
```

**Gestión del servicio systemd:**
```bash
# Iniciar servicio
sudo systemctl start onedrive-rclone@$(whoami).service

# Ver estado del servicio
sudo systemctl status onedrive-rclone@$(whoami).service

# Ver logs en tiempo real
journalctl -u onedrive-rclone@$(whoami).service -f

# Deshabilitar montaje automático
sudo systemctl disable onedrive-rclone@$(whoami).service
```

**Comandos manuales (sin servicio):**
```bash
# Montar OneDrive manualmente
rclone mount onedrive: ~/OneDrive --daemon --vfs-cache-mode writes --allow-other

# Desmontar OneDrive
fusermount -u ~/OneDrive

# Ver configuración actual
rclone config show
```

**Lo que hace el script:**
- Instala rclone automáticamente en Linux (apt/yum/dnf)
- Configura automáticamente `/etc/fuse.conf` para permitir `--allow-other`
- Crea servicio de sistema (no de usuario) para mayor estabilidad
- Montaje automático al arrancar usando systemd
- Incluye funciones de diagnóstico y reparación
- Completamente idempotente (se puede ejecutar múltiples veces)

### 3. Configurar SSH (opcional)

Configura el acceso SSH para gestionar tu servidor de forma segura, por defecto el script configura el acceso con claves públicas de GitHub de los usuarios definidos en `GITHUB_SSH_USERS` en el archivo `common.env`.

```bash
# Configurar acceso SSH
./scripts/setup-ssh.sh
```

### 4. Configurar variables de entorno

Edita los archivos de configuración necesarios en `config/private/`.

```bash
# Editar configuración común
nano config/private/common.env
nano config/private/cloudflare.env
...
```

### 5. Configurar autenticación (TinyAuth)

El sistema incluye **TinyAuth** para proteger tus servicios con autenticación simple usando Google OAuth. Configura las credenciales:

```bash
# 1. Obtener credenciales de Google OAuth
# Ve a https://console.developers.google.com/
# Crea un proyecto y configura OAuth 2.0

# 2. Configurar autenticación
nano config/private/auth.env
```

**Ejemplo de configuración en `auth.env`:**
```bash
# Google OAuth (obtener de Google Console)
GOOGLE_CLIENT_ID=tu-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=tu-client-secret

# Usuarios autorizados (emails separados por comas)
OAUTH_WHITELIST=tu-email@gmail.com,otro-email@gmail.com
```

**Configuración en Google Console:**
1. Ve a https://console.developers.google.com/
2. Crea nuevo proyecto o selecciona uno existente
3. Habilita "Google+ API" 
4. Ve a "Credentials" → "Create Credentials" → "OAuth 2.0 Client ID"
5. Tipo: Web application
6. Authorized redirect URIs: `https://auth.tu-dominio.com/api/auth/callback/google`

**Características del sistema de autenticación:**
- 🔐 **Login con Google OAuth** - Sin gestión de contraseñas
- ✅ **Whitelist de emails** - Solo usuarios autorizados
- 🚀 **Configuración simple** - Solo credenciales Google
- 🛡️ **Forward Auth** - Protege cualquier servicio con Traefik
- ⚡ **Liviano** - Minimal y rápido

Ver documentación completa: [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md)

### 6. Configurar seguridad del servidor (Opcional)

Para servidores en producción, configura protecciones adicionales:

```bash
# Configuración completa de seguridad
./scripts/setup-security.sh

# Solo Fail2Ban (protección SSH)
./scripts/setup-security.sh --fail2ban-only

# Solo actualizaciones automáticas
./scripts/setup-security.sh --auto-updates-only

# Ver estado de seguridad
./scripts/setup-security.sh --status
```

### 7. Configurar DNS automático (Opcional)

Revisar la sección de configuración de Cloudflare al final de este documento para obtener tu API Key/Token y configurar los registros DNS necesarios.

Si tienes IP dinámica o quieres automatizar la configuración DNS:

```bash
# Actualizar DNS de Cloudflare automáticamente
./scripts/update-dns.sh

# Ver qué cambios haría sin aplicarlos
./scripts/update-dns.sh --dry-run

# Ver registros DNS actuales
./scripts/update-dns.sh --list
```

### 8. Instalar Docker y Docker Compose (Ubuntu Server)

Si no tienes Docker y Docker Compose instalados, puedes usar el siguiente script para instalarlos en Ubuntu Server:

```bash
# Instalación completa (recomendado)
./scripts/install-docker.sh

# Ver opciones disponibles
./scripts/install-docker.sh --help

# Instalación sin optimizaciones del sistema
./scripts/install-docker.sh --skip-optimize
```

**Lo que instala el script:**
- Docker Engine y Docker Compose Plugin
- Dependencias básicas (curl, git, jq, htop, etc.)
- Optimizaciones del sistema para Docker

**Después de la instalación:**
- Verifica Docker: `docker run hello-world`

### Funcionalidades Avanzadas del Sistema de Deploy

El sistema de deploy incluye varias características avanzadas:

#### **🔨 Rebuild Automático de Imágenes**
- **✅ Detección automática**: Si hay `Dockerfile` en el stack, se rebuildea automáticamente
- **🚀 Caché inteligente**: 
  - Deploy normal: `docker compose build` (con caché, más rápido)
  - Con `--recreate`: `docker compose build --no-cache` (sin caché, más seguro)
- **📁 Búsqueda recursiva**: Detecta Dockerfiles en cualquier subdirectorio del stack

## 🚢 Despliegue de Servicios

### Despliegue automático (Recomendado)

El script `deploy.sh` es tu comando principal que se encarga de todo automáticamente:

```bash
# Despliegue completo automático
./scripts/deploy.sh

# El script automáticamente:
# ✅ Inicializa redes Docker necesarias
# ✅ Detecta cambios en configuración
# ✅ Regenera archivos .env si es necesario
# ✅ Despliega stacks en orden correcto
# ✅ Verifica que todo funcione correctamente
```

### Opciones de despliegue

```bash
# Desplegar stacks específicos
./scripts/deploy.sh platform home media helloworld

# Forzar despliegue sin detección de cambios
./scripts/deploy.sh --force

# Recrear contenedores completamente (incluye rebuild si hay Dockerfile)
./scripts/deploy.sh --recreate

# Ver información detallada del proceso
./scripts/deploy.sh --verbose

# Listar stacks disponibles
./scripts/deploy.sh --list

# Ver ayuda completa
./scripts/deploy.sh --help
```

### Despliegue manual (Para casos específicos)

Si necesitas control granular sobre el proceso:

```bash
# 1. Crear redes Docker manualmente
./scripts/setup-networks.sh

# 2. Generar archivos .env manualmente
./scripts/generate-docker-envs.sh

# 3. Levantar stacks individualmente
cd docker/platform && docker compose up -d    # Infraestructura completa (Traefik + TinyAuth + Watchtower)
cd ../home && docker compose up -d             # Dashboard principal del Home Server
cd ../helloworld && docker compose up -d       # Aplicaciones de usuario
```

## 🌐 Acceso a los Servicios

Una vez desplegado, podrás acceder a:

### 🔓 **Servicios Públicos (sin autenticación)**
- **Dashboard del Home Server**: `https://tu-dominio.com` (página principal)
- **Hello World App**: `https://hello.tu-dominio.com`

### 🔒 **Servicios Protegidos (requieren login)**
- **Traefik Dashboard**: `https://traefik.tu-dominio.com`
- **Panel de Autenticación**: `https://auth.tu-dominio.com`

### 🔐 **Flujo de Autenticación**

1. **Acceso a servicio protegido** (ej: Traefik Dashboard)
2. **Redirección automática** a `https://auth.tu-dominio.com`
3. **Login** con las credenciales configuradas
4. **Redirección de vuelta** al servicio original
5. **Acceso concedido** con sesión persistente

### 🛡️ **Configurar Más Servicios Protegidos**

Para proteger cualquier servicio nuevo, agrega esta etiqueta a su `docker-compose.yml`:
```yaml
labels:
  - "traefik.http.routers.tu-servicio.middlewares=tinyauth@docker"
```

> **Nota**: Asegúrate de que tu dominio esté configurado en Cloudflare y apunte a tu servidor.

## 📁 Compartir Archivos (NFS y Samba)

El sistema incluye gestión completa de compartidas de archivos a través de NFS y Samba/CIFS para acceder a tu biblioteca multimedia y descargas desde cualquier dispositivo de la red.

### Características

- **🗄️ NFS Server**: Para sistemas Unix/Linux (configuración manual)
- **💻 Samba/CIFS**: Para Windows/macOS (configuración automática)
- **⚙️ Una sola configuración**: Los shares en `stacks.yml` sirven para ambos protocolos
- **🔒 Gestión de permisos**: Lectura/escritura por share
- **📊 Configuración dinámica**: Samba se configura automáticamente al desplegar

### Configuración rápida

```bash
# 1. Configurar shares en stacks.yml (ya incluido en stack media)
# 2. Desplegar platform (configura Samba automáticamente)
./scripts/deploy.sh platform

# 3. Configurar NFS manualmente  
sudo ./scripts/nfs-manager.sh setup

# 4. Verificar estado
sudo ./scripts/nfs-manager.sh status
```

### Acceso desde clientes

**NFS (Linux/macOS):**
```bash
# Montar biblioteca multimedia (solo lectura)
sudo mount -t nfs servidor:/media/library /mnt/media

# Montar carpeta de descargas (lectura/escritura)  
sudo mount -t nfs servidor:/media/downloads /mnt/downloads
```

**Samba/CIFS (Windows/macOS/Linux):**
- **Windows**: `\\servidor\media_library`, `\\servidor\media_downloads`
- **macOS**: `smb://servidor/media_library`
- **Linux**: `sudo mount -t cifs //servidor/media_library /mnt/media`

Ver documentación completa: [docs/NFS_MANAGEMENT.md](docs/NFS_MANAGEMENT.md)

## 💾 Gestión de Backups

El sistema incluye un completo sistema de gestión de backups para proteger todos los datos importantes de tu home server.

### 🎯 ¿Qué se puede respaldar?

- **Configuración del sistema**: Archivos `.env` con todas las credenciales y configuraciones
- **Datos de aplicaciones**: Configuraciones de Radarr, Sonarr, Jellyfin, etc.
- **Metadatos multimedia**: Información de películas, series, configuraciones personalizadas
- **Base de datos**: Dumps de bases de datos de los servicios
- **Biblioteca multimedia**: Opcional, dependiendo del espacio disponible

### ⚙️ Sistema de Enlaces Dinámicos

El sistema utiliza enlaces simbólicos para permitir flexibilidad en la ubicación de backups:

#### Características

- **🔗 Enlace dinámico**: Configura la ruta de backups una vez y úsala en todos los scripts
- **📂 Estructura organizada**: Separación clara entre tipos de backup
- **🔄 Scripts automatizables**: Preparado para automatización con cron/systemd
- **💽 Soporte multi-destino**: Disco local, NAS, cloud storage, etc.

### 📋 Configuración Paso a Paso

#### 1. Preparar destino de backups

```bash
# Ejemplos de destinos comunes:

# Disco externo
mkdir -p /mnt/backup-drive/home-server-backups

# NAS montado
mkdir -p /mnt/nas/backups/home-server

# Directorio local
mkdir -p ~/Backups/home-server

# Cloud storage montado (OneDrive, Google Drive, etc.)
mkdir -p ~/OneDrive/Backups/home-server
```

#### 2. Configurar enlace de backups

```bash
# Configurar enlace usando el script principal
./scripts/link.sh backups /mnt/backup-drive/home-server-backups

# Ejemplos con diferentes destinos:
./scripts/link.sh backups /mnt/nas/backups/home-server
./scripts/link.sh backups ~/Backups/home-server
./scripts/link.sh backups ~/OneDrive/Backups/home-server
```

#### 3. Verificar configuración

```bash
# Verificar que el enlace funciona
ls -la data/backups

# Debe mostrar algo como:
# lrwxrwxrwx 1 user user 35 Nov 12 10:30 data/backups -> /mnt/backup-drive/home-server-backups

# Probar escritura (crear archivo de prueba)
echo "test" > data/backups/test.txt && rm data/backups/test.txt
echo "✅ Enlace configurado correctamente"
```

### 🗂️ Estructura de Backups

Una vez configurado, el sistema organizará los backups con esta estructura recomendada:

```
/tu/directorio/backups/
├── config/                     # 📁 Backups de configuración
│   ├── 20251112-130500-config.tar.gz
│   ├── 20251111-130500-config.tar.gz
│   └── latest -> 20251112-130500-config.tar.gz
├── databases/                  # 🗄️ Dumps de bases de datos
│   ├── 20251112-jellyfin-db.sql
│   ├── 20251111-jellyfin-db.sql
│   └── latest/
│       └── jellyfin-db.sql -> ../20251112-jellyfin-db.sql
├── media-metadata/             # 🎬 Configuración de servicios de media
│   ├── 20251112-000000/
│   │   ├── radarr-config.tar.gz
│   │   ├── sonarr-config.tar.gz
│   │   ├── jellyfin-config.tar.gz
│   │   └── prowlarr-config.tar.gz
│   ├── 20251111-000000/
│   └── latest -> 20251112-000000/
├── docker-volumes/             # 🐳 Backups de volúmenes Docker críticos
│   ├── 20251112-volumes.tar.gz
│   └── latest -> 20251112-volumes.tar.gz
└── logs/                       # 📝 Logs de operaciones de backup
    ├── backup-20251112.log
    ├── backup-20251111.log
    └── latest.log -> backup-20251112.log
```

### 🔧 Cambiar Destino de Backups

Si necesitas cambiar la ubicación de tus backups:

```bash
# 1. Opcional: Mover backups existentes
cp -r data/backups/* /nueva/ubicacion/backups/

# 2. Reconfigurar enlace
./scripts/link.sh backups /nueva/ubicacion/backups

# 3. Verificar nuevo enlace
ls -la data/backups
```

### 💡 Consejos y Mejores Prácticas

```


### 🚀 Scripts de Backup Automatizados

El sistema incluye un script completamente funcional para crear backups automáticos:

```bash
# Backup de stacks específicos
./scripts/backup.sh media platform

# Backup de todos los stacks
./scripts/backup.sh --all

# Backup seguro (detiene servicios antes del backup)
./scripts/backup.sh --safe media

# Backup con lista detallada de archivos
./scripts/backup.sh --verbose media

# Limpiar backups antiguos (mantener solo los 5 más recientes)
./scripts/backup.sh --cleanup
./scripts/backup.sh --cleanup 10  # Mantener 10 por stack

# Ver ayuda completa
./scripts/backup.sh --help
```

**Características del script:**
- **🎯 Configuración por stack**: Cada stack puede tener exclusiones específicas en `stacks.yml`
- **📁 Respaldo inteligente**: Solo incluye contenido de `data/{stack}` 
- **🚫 Exclusiones gitignore**: Patrones como `**/*.zip`, directorios específicos
- **📅 Timestamps**: Archivos con fecha y hora `stack-YYYYMMDD-HHMMSS.tar.gz`
- **📊 Estadísticas**: Tamaño y número de archivos incluidos, top 5 archivos más grandes
- **🔒 Modo seguro**: Detiene servicios antes del backup para garantizar consistencia
- **⚡ Backup completo**: Opción `--all` para respaldar todos los stacks
- **🧹 Limpieza automática**: Elimina backups antiguos manteniendo solo los más recientes

### 🔄 Restauración de Backups

El script de backup también permite restaurar backups de forma interactiva y segura usando `fzf`:

#### Requisitos

```bash
# Instalar fzf si no lo tienes
# Ubuntu/Debian:
sudo apt install fzf

# macOS:
brew install fzf

# Fedora/RHEL:
sudo dnf install fzf
```

#### Uso

```bash
# Restaurar: mostrar menú de selección de todos los backups (con fzf)
./scripts/backup.sh --restore

# Restaurar: mostrar solo backups de un stack específico
./scripts/backup.sh --restore media

# Restaurar un archivo de backup específico (sin menú)
./scripts/backup.sh --restore /ruta/completa/a/media-20251112-120000.tar.gz
```

**Características del restore:**
- **📋 Menú interactivo con fzf**: Búsqueda incremental, preview de contenido del backup
- **🔍 Filtro por stack**: Muestra solo backups de un stack específico
- **⚠️ Confirmación de sobrescritura**: Solicita confirmación antes de restaurar
- **💾 Backup de seguridad automático**: Crea backup del estado actual antes de restaurar (respetando exclusiones)
- **🛑 Gestión de servicios**: Detiene servicios automáticamente antes de restaurar
- **🔒 Respeta exclusiones**: El backup de seguridad y la restauración respetan las exclusiones configuradas
- **✅ Sobrescritura inteligente**: Solo sobrescribe archivos del backup, mantiene otros archivos (ej: directorios excluidos)
- **🔄 Reinicio automático**: Reinicia servicios después de restaurar

**Comportamiento importante:**
- ⚠️ **NO borra todo el contenido** del stack - solo sobrescribe archivos que están en el backup
- 💡 Archivos en directorios excluidos (ej: `library/`, `downloads/`) se mantienen intactos
- 📦 El backup de seguridad pre-restore también respeta las exclusiones para ser consistente
- 🔐 Ideal para restaurar configuraciones sin afectar datos grandes (bibliotecas multimedia, descargas, etc.)

**Ejemplo de uso con fzf:**

```bash
$ ./scripts/backup.sh --restore media

📦 Buscando backups disponibles...

# Se abre fzf con:
# - Lista de backups con tamaño y fecha
# - Preview del contenido (primeros 20 archivos)
# - Búsqueda incremental
# - Navegación con flechas o búsqueda por texto

> media-20251112-120000.tar.gz      195M  2025-11-12 12:00:00
  media-20251111-093000.tar.gz      192M  2025-11-11 09:30:00
  media-20251110-143000.tar.gz      189M  2025-11-10 14:30:00
  ...

# Al seleccionar un backup:

🔄 Iniciando restore del backup: media-20251112-120000.tar.gz
📦 Stack destino: media
⚠️ ADVERTENCIA: El directorio contiene 1747 archivos
⚠️ Esta operación SOBRESCRIBIRÁ los datos existentes

¿Estás seguro de continuar? (escribe 'SI' para confirmar): SI

🔍 Servicios detectados para stack 'media'
🛑 Deteniendo servicios del stack: media
✅ Servicios detenidos correctamente
⏳ Esperando 5 segundos para que se liberen los archivos...
💾 Creando backup del estado actual antes de restaurar...
✅ Backup de seguridad creado: media-pre-restore-20251113-125530.tar.gz (12M)
📦 Restaurando backup...
📁 Destino: /homeserver/data/media
ℹ️ Los archivos del backup sobrescribirán los existentes
📄 Archivos a restaurar: 1747
✅ Backup restaurado exitosamente
📊 Tamaño total del stack: 195M
📄 Total de archivos en el stack: 2150
🔄 Reiniciando servicios del stack: media
✅ Servicios iniciados correctamente
🎉 Restore completado exitosamente
```

**Nota sobre el tamaño:**
En el ejemplo anterior, el backup tiene 1747 archivos pero el stack final tiene 2150 archivos. Esto es normal porque:
- El backup excluye directorios como `library/`, `downloads/`, etc.
- Estos archivos excluidos se mantienen intactos durante la restauración
- Solo se sobrescriben los archivos de configuración que están en el backup

## 🤖 Mantenimiento Automático

El sistema incluye un completo sistema de mantenimiento automático que se ejecuta en segundo plano para mantener tu servidor funcionando de forma óptima.

### Configurar automatización

```bash
# Instalar todas las tareas automáticas (recomendado)
./scripts/auto-maintenance.sh --install

# Ver estado de las tareas automáticas
./scripts/auto-maintenance.sh --status

# Ver logs de ejecuciones automáticas
./scripts/auto-maintenance.sh --logs
```

### ¿Qué hace el mantenimiento automático?

**Tareas que se ejecutan automáticamente:**

- **🔄 DNS + Servicios** (cada 30 min): Actualiza Cloudflare DNS y verifica que todos los contenedores estén funcionando
- **📅 Mantenimiento diario** (2:00 AM): Tareas básicas de mantenimiento (sin backup)
- **📦 Mantenimiento semanal** (Domingos 3:00 AM): Backup automático de todos los stacks + limpieza de logs antiguos
- **🚀 Recuperación al inicio**: Ejecuta tareas perdidas si el PC estuvo apagado

**Ventajas de esta organización:**
- ⚡ **Backup semanal en vez de diario**: Menos carga, más eficiente
- 🎯 **Tareas agrupadas lógicamente**: DNS y servicios van juntos (cada 30 min)
- 🧹 **Limpieza semanal**: Coincide con el backup
- 📋 **Cron más limpio**: Solo 4 entradas en vez de 5

### Gestión manual del mantenimiento

```bash
# Ejecutar mantenimiento completo ahora (DNS + servicios + backup + limpieza)
./scripts/auto-maintenance.sh --run-now

# Solo actualizar DNS ahora
./scripts/auto-maintenance.sh --dns-only

# Solo verificar servicios
./scripts/auto-maintenance.sh --check-only

# Solo hacer backup
./scripts/auto-maintenance.sh --backup-only

# Solo limpiar logs
./scripts/auto-maintenance.sh --cleanup-only

# Ejecutar tarea periódica (DNS + servicios)
./scripts/auto-maintenance.sh --periodic

# Ejecutar mantenimiento diario
./scripts/auto-maintenance.sh --daily

# Ejecutar mantenimiento semanal (backup + limpieza)
./scripts/auto-maintenance.sh --weekly

# Desinstalar automatización
./scripts/auto-maintenance.sh --uninstall
```

### Logs y monitoreo

Todos los logs se guardan automáticamente en `data/logs/maintenance.log`:

```bash
# Ver últimos logs
./scripts/auto-maintenance.sh --logs

# Ver logs en tiempo real
tail -f data/logs/maintenance.log

# Ver solo actividad DNS
grep "DNS" data/logs/dns-update.log
```

**Ejemplo de logs:**
```
[2024-10-24 14:30:00] 🔄 Iniciando actualización automática de DNS...
[2024-10-24 14:30:02] ✅ IP detectada: 192.168.1.100
[2024-10-24 14:30:03] ⏭️ ejemplo.com ya apunta a 192.168.1.100 (sin cambios)
[2024-10-24 14:30:04] ✅ Todos los servicios están corriendo correctamente
```

### Ventajas del sistema automático

- **🔧 Set & Forget**: Una vez instalado, funciona completamente solo
- **📱 IP dinámica**: Perfecto si tu IP cambia frecuentemente
- **🛡️ Alta disponibilidad**: Detecta y reporta servicios caídos
- **📊 Logs completos**: Sabes exactamente qué pasó y cuándo
- **🔄 Recuperación**: Si el PC se apaga, recupera tareas perdidas al encender

## 🔄 Deployment Automático desde GitHub

El sistema incluye deployment automático que se ejecuta cada vez que haces commit en GitHub.

### Configuración rápida

1. **Generar clave SSH en tu servidor:**
   ```bash
   ssh-keygen -t rsa -b 4096 -C "github-actions@home-server" -f ~/.ssh/github-actions
   cat ~/.ssh/github-actions.pub >> ~/.ssh/authorized_keys
   ```

2. **Configurar GitHub Secrets:**
   - Ve a tu repositorio → Settings → Secrets and variables → Actions
   - Añade estas variables de entorno:
     - `SSH_PRIVATE_KEY`: Contenido de `~/.ssh/github-actions`
     - `SSH_HOST`: IP o dominio de tu servidor
     - `SSH_USER`: Tu usuario SSH
     - `PROJECT_PATH`: Ruta del proyecto (ej: `/home/usuario/home-server`)

3. **¡Listo!** Ahora cada `git push` desplegará automáticamente

### Características del deployment automático

- **🔄 Automático**: Se ejecuta con cada commit a main/master
- **🎯 Inteligente**: Solo redespliega servicios que cambiaron
- **📊 Monitoreable**: Logs completos en GitHub Actions y servidor
- **🔒 Seguro**: Conexión SSH con clave específica
- **⚙️ Configurable**: Deployment manual con opciones avanzadas

### Deployment manual desde GitHub

Puedes ejecutar deployment manual:
1. Ve a GitHub → Actions → "Deploy Home Server"
2. Click "Run workflow"
3. Selecciona opciones:
   - Force deploy all stacks
   - Recreate containers completely

Ver documentación completa: [docs/AUTO_DEPLOYMENT.md](docs/AUTO_DEPLOYMENT.md)

## 🔧 Comandos Útiles

### Gestión principal

```bash
# Despliegue completo automático (comando principal)
./scripts/deploy.sh

# Redesplegar solo servicios específicos
./scripts/deploy.sh platform home helloworld

# Forzar regeneración de archivos .env
./scripts/deploy.sh --force-envs

# Ver estado de los servicios
./scripts/deploy.sh --list

# Ver configuración de TinyAuth
nano config/private/auth.env
```

### Gestión de configuración

```bash
# Ver configuración actual de variables por stack
./scripts/generate-docker-envs.sh --list

# Regenerar archivos .env manualmente
./scripts/generate-docker-envs.sh

# Actualizar DNS de Cloudflare
./scripts/update-dns.sh

# Ver estado de seguridad del servidor
./scripts/setup-security.sh --status
```

### Docker avanzado

```bash
# Ver logs en tiempo real de un stack específico
docker compose -f docker/platform/docker-compose.yml logs -f
docker compose -f docker/helloworld/docker-compose.yml logs -f

# Reiniciar servicios manualmente
docker compose -f docker/helloworld/docker-compose.yml restart

# Parar stack específico
docker compose -f docker/platform/docker-compose.yml down

# Verificar redes Docker
docker network ls | grep proxy

# Limpiar sistema Docker
docker system prune -af
```



## 🔒 Configuración de Cloudflare

### Obtener API Key/Token

1. **API Key Global** (opción 1):
   - Ve a Cloudflare Dashboard → Mi perfil → Tokens API
   - Copia la "Global API Key"

2. **Token DNS específico** (recomendado):
   - Ve a Cloudflare Dashboard → Mi perfil → Tokens API
   - Crear token personalizado con permisos:
     - `Zone:DNS:Edit` para tu dominio
     - `Zone:Zone:Read` para tu dominio

### Configurar DNS

Asegúrate de que tu dominio tenga registros A/AAAA apuntando a tu servidor:

```
Type: A
Name: @
Content: tu-ip-publica
Proxy: Desactivado (nube gris)

Type: A  
Name: *
Content: tu-ip-publica
Proxy: Desactivado (nube gris)
```

## 🛠️ Troubleshooting

### Problema: Certificados SSL no se generan

```bash
# Verificar logs de Traefik
docker logs traefik | grep -i "acme\|certificate"

# Verificar configuración de Cloudflare
docker exec traefik cat /etc/traefik/dynamic/middlewares.yml
```

### Problema: No se puede acceder a los servicios

```bash
# Verificar que la red Docker existe
docker network ls | grep proxy

# Verificar que los servicios están en la red correcta
docker network inspect proxy

# Verificar DNS local
nslookup hello.tu-dominio.com

# Verificar estado de contenedores
./scripts/deploy.sh --list
```

### Problema: Permisos de archivos

```bash
# Verificar permisos de volúmenes Docker
docker volume inspect traefik_certs traefik_logs

# Corregir permisos si es necesario
sudo chown -R 1000:1000 /var/lib/docker/volumes/traefik_*

# O reiniciar contenedores para que Docker reconfigure permisos
./scripts/deploy.sh --recreate platform
```

## 🔄 Próximos Pasos

Una vez que tengas funcionando el stack completo con autenticación, puedes:

1. **Añadir más usuarios** al sistema de autenticación (whitelist)
2. **Proteger servicios adicionales** con el middleware de TinyAuth
3. **Crear nuevos stacks** (multimedia, monitoring, etc.)
4. **Configurar backup automático** de la carpeta `data/`
5. **Personalizar configuración** de TinyAuth según necesidades

## 📝 Notas Importantes

- La configuración privada nunca se sube al repositorio (está en `config/private/`)
- Los archivos `.env` en `docker/*/` se generan automáticamente
- Los datos persistentes se guardan en `data/`
- Traefik maneja automáticamente los certificados SSL

### Limpieza y Redespliegue Completo

Si necesitas una limpieza completa (útil después de reorganizaciones o cambios mayores):

```bash
# Ver qué haría sin ejecutar
./scripts/clean-deploy.sh --dry-run

# Limpieza completa (para todo y redesplega)
./scripts/clean-deploy.sh --verbose

# Limpieza sin confirmación
./scripts/clean-deploy.sh --force
```

**¿Cuándo usar este script?**
- Después de reorganizar stacks
- Cuando hay contenedores huérfanos corriendo
- Para limpieza completa del sistema Docker
- Cuando el deploy normal no elimina servicios antiguos

**Lo que hace (agnóstico):**
- Para TODOS los contenedores del sistema
- Ejecuta deploy completo desde cero
- Elimina contenedores huérfanos (que no se levantaron)
- Limpia recursos Docker no utilizados
- Verifica estado final

### Gestión de información de stacks

El sistema utiliza un archivo YAML (`config/stacks.yml`) para centralizar toda la configuración de stacks y servicios:

```bash
# Ver servicios de stacks específicos
./scripts/stack-info.sh services platform home media helloworld

# Listar toda la configuración de stacks
./scripts/stack-info.sh list

# Ver configuración de un stack específico
./scripts/stack-info.sh config platform

# Ver ayuda completa
./scripts/stack-info.sh help
```

**Formato del archivo `config/stacks.yml`:**
```yaml
stacks:
  home:
    description: "Página principal del Home Server con información dinámica"
    config_files: []  # Solo usa common.env
    services:
      web:
        subdomain: ""  # Sin subdominio (dominio principal)
        description: "🏠 Home Server Dashboard"
        protected: false
  
  helloworld:
    description: "Servicio de ejemplo Hello World"
    config_files:
      - helloworld    # Usa config/private/helloworld.env
    services:
      hello:
        subdomain: hello
        description: "👋 Página de bienvenida Hello World"
        protected: false
```

**Ventajas del formato YAML:**
- 📖 **Más legible** que el formato anterior
- 🏗️ **Bien estructurado** con jerarquía clara
- ✅ **Validable** con herramientas YAML estándar  
- 📝 **Comentarios** y documentación integrados
- 🔧 **Extensible** para futuras funcionalidades

---

## 🔄 Actualizar HMS en el Servidor

Cuando hagas cambios en el repositorio (código Python, Docker, configuración), necesitas actualizar el contenedor HMS en el servidor.

### Opción A: Actualización Manual (Recomendado para cambios pequeños)

Ejecuta el script de actualización en el servidor:

```bash
cd /ruta/home-server
./update.sh
```

**Qué hace:**
1. Hace `git pull` para traer cambios del repositorio
2. Detecta cambios en `hms/`, `docker/hms/`, `pyproject.toml`
3. Si hay cambios relevantes:
   - Para el contenedor actual
   - Rebuilda la imagen Docker sin caché
   - Levanta el contenedor actualizado
4. Valida que el contenedor está corriendo

**Ejemplo de salida:**
```
🔄 HMS Updater
📊 Comparando cambios...
⬇️  Haciendo git pull...
✅ Nuevo commit: abc123def456...
📝 Cambios detectados en:
hms/plugins/stacks/up.py
docker/hms/Dockerfile
🔨 Reconstruyendo imagen Docker...
🛑 Parando contenedor hms...
🗑️  Eliminando contenedor hms...
📦 Construyendo nueva imagen...
🚀 Levantando nuevo contenedor...
✅ Contenedor HMS actualizado y corriendo
✅ Actualización completada
```

### Comportamiento especial

- **Sin cambios relevantes:** Sale sin hacer nada
- **Docker no disponible:** Trae cambios pero no rebuilda
- **Conflictos en git:** Aborta y pide resolverlos manualmente

### Futuro: Webhook automático

Después, podremos integrar un webhook de GitHub para que se actualice automáticamente al hacer push al repositorio.
