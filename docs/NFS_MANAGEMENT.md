# Gestión de Shares (NFS y Samba)

Sistema para compartir archivos en red usando NFS (gestionado manualmente) y Samba (configurado dinámicamente).

## 📋 Descripción General

El sistema de shares permite exponer directorios del home server a través de:
- **NFS**: Configurado manualmente usando `nfs-manager.sh` 
- **Samba/CIFS**: Configurado dinámicamente desde los shares definidos en `stacks.yml`

## Script nfs-manager.sh

Script principal para configurar y gestionar las compartidas NFS basándose en la configuración definida en `config/stacks.yml`. Utiliza las funciones genéricas de shares del sistema.

### Uso

```bash
# Configurar NFS (requiere sudo)
sudo ./scripts/nfs-manager.sh setup

# Ver estado de las compartidas
./scripts/nfs-manager.sh status

# Remover configuración NFS
sudo ./scripts/nfs-manager.sh remove

# Mostrar ayuda
./scripts/nfs-manager.sh help
```

## 📁 Configuración en stacks.yml

Las shares se configuran en la sección `shares` de cada stack (excepto platform):

```yaml
stacks:
  media:
    shares:
      media_library:
        path: "/library"                   # Relativo a data/media/
        exposed_path: "/media/library"
        description: "Biblioteca multimedia (películas y series)"
        permissions: "ro"
      downloads:
        path: "/downloads"                 # Relativo a data/media/
        exposed_path: "/media/downloads"
        description: "Carpeta de descargas activas"
        permissions: "rw"
```

**Campos de configuración:**
- **`path`**: Ruta en el servidor donde están los archivos. Los paths que comienzan con `/` se interpretan como relativos a `data/media/` del repositorio
- **`exposed_path`** *(opcional)*: Ruta que se expone a los clientes NFS. Si no se especifica, se usa `path`
- **`permissions`**: `"ro"` (solo lectura) o `"rw"` (lectura/escritura)
- **`description`**: Descripción legible de la compartida

**Conversión automática de paths:**
- `/library` → `{repositorio}/data/media/library`
- `/downloads/complete` → `{repositorio}/data/media/downloads/complete` 
- `/data/external/media` → `/data/external/media` (path absoluto, se mantiene)

## 🚀 Servicios Incluidos

### **NFS Server** (Configuración Manual)
- Gestión manual usando `nfs-manager.sh`
- Configuración de `/etc/exports` 
- Bind mounts para paths expuestos

### **Samba/CIFS Server** (Configuración Automática)
- Servidor Samba en stack platform
- Configuración automática via `pre-deploy.sh`
- Genera `docker-compose.override.yml` dinámicamente
- Crea `smb.conf` automáticamente

## 📜 Scripts de Gestión

### **NFS (Manual)**
```bash
# Configurar NFS basado en shares
sudo ./scripts/nfs-manager.sh setup

# Ver estado de shares NFS
sudo ./scripts/nfs-manager.sh status

# Remover configuración NFS
sudo ./scripts/nfs-manager.sh remove
```

### **Samba (Automático)**
```bash
# Se configura automáticamente al desplegar platform
./scripts/deploy.sh platform
```

## 🌐 Acceso desde Clientes

### **NFS (Linux/macOS)**
```bash
# Montar library (solo lectura) 
sudo mount -t nfs -o vers=3,tcp,resvport servidor:/media/library /mnt/library

# Montar downloads (lectura/escritura)
sudo mount -t nfs -o vers=3,tcp,resvport servidor:/media/downloads /mnt/downloads
```

### **Samba/CIFS (Windows/macOS/Linux)**
```bash
# Windows (En explorador de archivos)
\\servidor-ip\media_library
\\servidor-ip\media_downloads

# Linux
sudo mount -t cifs //servidor/media_library /mnt/library -o username=apocaly,password=...

# macOS
smb://servidor/media_library
```

### Montaje permanente en clientes

Una vez configurado NFS en el servidor, puedes montar las compartidas permanentemente:

```bash
# Crear punto de montaje
sudo mkdir -p /mnt/homeserver-media

# Montar compartida
sudo mount -t nfs SERVER_IP:/media/library /mnt/homeserver-media

# Montaje permanente en /etc/fstab
echo "SERVER_IP:/media/library /mnt/homeserver-media nfs defaults 0 0" | sudo tee -a /etc/fstab
```

## 🔒 Configuración de Seguridad

### **Variables de Samba** (config/private/platform.env)
```bash
SAMBA_WORKGROUP=WORKGROUP
SAMBA_USERNAME=apocaly
SAMBA_PASSWORD=password_segura
```

### **Usuarios NFS**
- Se usan `PUID/PGID` del archivo common.env
- Los archivos mantienen ownership correcto automáticamente

## 📊 Funcionamiento del Sistema

### **1. Configuración NFS (Manual)**
1. Definir shares en `stacks.yml` de cada stack
2. Ejecutar `sudo ./scripts/nfs-manager.sh setup`
3. NFS expondrá las rutas según `exposed_path`

### **2. Configuración Samba (Automática)**
1. Al ejecutar `./scripts/deploy.sh platform`:
2. `pre-deploy.sh` busca todos los shares en todos los stacks
3. Genera `docker-compose.override.yml` con los volúmenes necesarios
4. Genera `smb.conf` con la configuración de cada share
5. Samba expone shares con nombres `{stack}_{share}`

### **3. Estructura resultante**
```
# NFS (manual, según exposed_path)
/media/library               # Biblioteca multimedia (RO)
/media/downloads             # Descargas activas (RW)

# Samba (automático, generado)
\\servidor\media_library     # Biblioteca multimedia (RO)  
\\servidor\media_downloads   # Descargas activas (RW)
```

## 🛠️ Deploy y Configuración

```bash
# 1. Desplegar stack platform (configura Samba automáticamente)
./scripts/deploy.sh platform

# 2. Configurar NFS manualmente
sudo ./scripts/nfs-manager.sh setup

# 3. Verificar estado
sudo ./scripts/nfs-manager.sh status
docker ps | grep samba
```

## ⚡ Ventajas del Sistema

- ✅ **Samba automático**: Se configura solo basándose en shares existentes
- ✅ **NFS manual**: Control total sobre configuración NFS
- ✅ **Una sola configuración**: Los shares en `stacks.yml` sirven para ambos
- ✅ **Sin duplicación**: Platform no tiene shares propios
- ✅ **Dinámico**: Añadir shares a cualquier stack actualiza Samba automáticamente

### Características

- ✅ Configuración automática basada en `stacks.yml`
- ✅ Creación automática de directorios
- ✅ Gestión de permisos (ro/rw)
- ✅ Logging detallado
- ✅ Validación de prerequisitos
- ✅ Interfaz de comandos simple

### Requisitos

- Ubuntu/Debian con `nfs-kernel-server`
- `yq` para procesar YAML
- Permisos de root para configuración NFS

El script instalará automáticamente las dependencias necesarias.
