# Home Server Setup

## 🚀 Stack Hello World + Traefik + Cloudflare DNS

Este proyecto configura un servidor doméstico con:
- **Traefik** como proxy inverso con SSL automático
- **Cloudflare DNS Challenge** para certificados Let's Encrypt
- **Hello World** como aplicación de prueba
- **Gestión centralizada de configuración y variables de entorno**

## 📁 Estructura del Proyecto

```
home-server/
├── config/
│   ├── templates/           # Plantillas de configuración
│   ├── stack-envs.conf      # Configuración de variables por stack
│   └── private -> /ruta/config  # Enlace a tu configuración (crear)
├── docker/
│   ├── network/            # Stack de infraestructura (Traefik)
│   └── helloworld/         # Stack de aplicación de prueba
├── scripts/                # Scripts de automatización
│   ├── deploy.sh           # Script principal de despliegue
│   ├── install-docker.sh   # Instalación de Docker (Ubuntu)
│   ├── setup-security.sh   # Configuración de seguridad del servidor
│   ├── setup-ssh.sh        # Configuración SSH con claves de GitHub
│   ├── update-dns.sh       # Actualización automática de DNS Cloudflare
│   └── auto-maintenance.sh # Mantenimiento automático programado
└── data/                   # Datos persistentes (volúmenes Docker)
```

## ⚙️ Configuración Inicial

### 1. Configurar carpeta de entorno

Crea una carpeta fuera del repositorio para almacenar tus archivos de configuración de entorno (API keys, contraseñas, etc.) y enlázala al proyecto. En el caso de que no existan previamente el script los creará automáticamente a partir de las plantillas.

```bash
# Crear carpeta de configuración donde quieras (fuera del repo)
mkdir -p ~/config/home-server

# Enlazar la carpeta de configuración
./scripts/link-config.sh ~/config/home-server
```

### 2. Instalar y configurar OneDrive (opcional)

Si necesitas sincronizar archivos con OneDrive, puedes instalar y configurar rclone para montarlo automáticamente:

```bash
# Instalar rclone y configurar OneDrive
./scripts/install-onedrive.sh

# Diagnosticar problemas del servicio
./scripts/install-onedrive.sh diagnose

# Reparar configuración si hay problemas
./scripts/install-onedrive.sh repair
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

### 5. Configurar seguridad del servidor (Opcional)

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

### 6. Configurar DNS automático (Opcional)

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

### 7. Instalar Docker y Docker Compose (Ubuntu Server)

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
./scripts/deploy.sh network helloworld

# Forzar despliegue sin detección de cambios
./scripts/deploy.sh --force

# Recrear contenedores completamente
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
cd docker/network && docker-compose up -d      # Traefik primero
cd ../helloworld && docker-compose up -d       # Servicios después
```

## 🌐 Acceso a los Servicios

Una vez desplegado, podrás acceder a:

- **Hello World App**: `https://hello.tu-dominio.com`
- **Traefik Dashboard**: `https://traefik.tu-dominio.com`

> **Nota**: Asegúrate de que tu dominio esté configurado en Cloudflare y apunte a tu servidor.

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

- **📡 Actualización DNS** (cada 30 min): Detecta cambios en tu IP pública y actualiza Cloudflare automáticamente
- **🔍 Monitoreo de servicios** (cada 5 min): Verifica que todos los contenedores estén funcionando
- **🧹 Limpieza de logs** (semanal): Elimina logs antiguos y rota archivos grandes
- **🔄 Mantenimiento completo** (diario a las 2:00 AM): Ejecuta todas las tareas de mantenimiento

### Gestión manual del mantenimiento

```bash
# Ejecutar mantenimiento completo ahora
./scripts/auto-maintenance.sh --run-now

# Solo actualizar DNS ahora
./scripts/auto-maintenance.sh --dns-only

# Solo verificar servicios
./scripts/auto-maintenance.sh --check-only

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
./scripts/deploy.sh network helloworld

# Forzar regeneración de archivos .env
./scripts/deploy.sh --force-envs

# Ver estado de los servicios
./scripts/deploy.sh --list
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
docker-compose -f docker/network/docker-compose.yml logs -f

# Reiniciar servicios manualmente
docker-compose -f docker/helloworld/docker-compose.yml restart

# Parar stack específico
docker-compose -f docker/network/docker-compose.yml down

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
./scripts/deploy.sh --recreate network
```

## 🔄 Próximos Pasos

Una vez que tengas funcionando el stack Hello World, puedes:

1. **Añadir más servicios** al stack helloworld
2. **Crear nuevos stacks** (multimedia, monitoring, etc.)
3. **Configurar backup automático** de la carpeta `data/`
4. **Añadir autenticación** usando los middlewares de Traefik

## 📝 Notas Importantes

- La configuración privada nunca se sube al repositorio (está en `config/private/`)
- Los archivos `.env` en `docker/*/` se generan automáticamente
- Los datos persistentes se guardan en `data/`
- Traefik maneja automáticamente los certificados SSL
