# Gestión de NFS para Home Server

Este directorio contiene los scripts para gestionar las compartidas NFS del home server.

## Script nfs-manager.sh

Script principal para configurar y gestionar las compartidas NFS basándose en la configuración definida en `config/stacks.yml`.

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

### Configuración en stacks.yml

Para que un stack tenga compartidas NFS, añade la sección `nfs_shares`:

```yaml
stacks:
  mi_stack:
    description: "Mi stack de ejemplo"
    config_files: []
    nfs_shares:
      mi_compartida:
        path: "/ruta/real/en/servidor"           # Ruta real en el sistema de archivos
        exposed_path: "/ruta/expuesta/por/nfs"   # Ruta que verán los clientes (opcional)
        description: "Descripción de la compartida"
        permissions: "ro"  # "ro" para solo lectura, "rw" para lectura/escritura
    services:
      # ... servicios del stack
```

**Campos de configuración:**
- **`path`**: Ruta real en el servidor donde están los archivos
- **`exposed_path`** *(opcional)*: Ruta que se expone a los clientes NFS. Si no se especifica, se usa `path`
- **`permissions`**: `"ro"` (solo lectura) o `"rw"` (lectura/escritura)
- **`description`**: Descripción legible de la compartida

**Ejemplo con exposed_path:**
```yaml
nfs_shares:
  media_library:
    path: "/data/media/library"        # Ruta real en el servidor
    exposed_path: "/media/library"     # Ruta simple para clientes
    description: "Biblioteca multimedia"
    permissions: "ro"
```

### Montaje en clientes

Con `exposed_path` configurado, los clientes acceden usando la ruta expuesta:

```bash
# Montar usando la ruta expuesta
sudo mount -t nfs SERVER_IP:/media/library /mnt/media

# En lugar de la ruta real del servidor
# sudo mount -t nfs SERVER_IP:/data/media/library /mnt/media
```

### Montaje en clientes

Una vez configurado NFS en el servidor, puedes montar las compartidas en otros dispositivos:

```bash
# Crear punto de montaje
sudo mkdir -p /mnt/homeserver-media

# Montar compartida
sudo mount -t nfs SERVER_IP:/data/media/library /mnt/homeserver-media

# Montaje permanente en /etc/fstab
echo "SERVER_IP:/data/media/library /mnt/homeserver-media nfs defaults 0 0" | sudo tee -a /etc/fstab
```

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
