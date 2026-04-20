# Referencia de Comandos CLI - HMS

Guía completa de todos los comandos disponibles en HMS.

## 📋 Estructura General de Comandos

```
hms <acción> [stack[,stack]] [argumentos]   # Comando de stack
hms <comando> [subcomando] [argumentos]     # Comando global
```

### Flags Globales

| Flag | Descripción |
|------|-------------|
| `-h` `--help` | Mostrar ayuda |

## 🎯 Comandos Globales

### install
Instalar HMS y crear symlink

```bash
hms install
hms install --force    # Reinstalar
```

### uninstall
Desinstalar HMS y eliminar symlink

```bash
hms uninstall
```

### start
Iniciar HMS y stacks habilitados

```bash
hms start
```

### stop
Detener HMS y todos los stacks

```bash
hms stop
```

### self-update
Actualizar HMS desde el repositorio (git pull + rebuild del contenedor)

```bash
hms self-update
```

### list
Listar stacks disponibles

```bash
hms list
```

### system
Comandos de administración del sistema

#### system backup
Crear y restaurar backups de stacks

```bash
# Crear backups
hms system backup                        # Todos los stacks + hms
hms system backup create                 # Todos los stacks + hms
hms system backup --stack media          # Stack específico
hms system backup --hms-only             # Solo hms (infra + config)
hms system backup --dry-run              # Simular sin ejecutar
hms system backup --force                # Ignorar enabled=false
hms system backup --no-rotate            # No eliminar backups antiguos

# Listar backups
hms system backup list

# Restaurar backups
hms system backup restore --file hms_20240219-143000.tar.gz
hms system backup restore --file media_20240219-143000.tar.gz
hms system backup restore --file hms_20240219-143000.tar.gz --dry-run
```

#### system reload-jobs
Recargar jobs del scheduler

```bash
hms system reload-jobs
```

#### system update-stacks
Actualizar imágenes Docker de todos los stacks habilitados (excepto infra)

```bash
hms system update-stacks
```

#### system update-infra
Actualizar imágenes Docker del stack de infraestructura (Traefik + TinyAuth)

```bash
hms system update-infra
```

#### system update-dns
Actualizar registros DNS en Cloudflare

```bash
hms system update-dns                    # Detectar IP automáticamente
hms system update-dns --ip 1.2.3.4       # Usar IP específica
hms system update-dns --dry-run          # Simular sin ejecutar
hms system update-dns --force            # Forzar actualización
hms system update-dns --list             # Listar registros DNS actuales
hms system update-dns --domain midominio.com  # Dominio específico
```

## 🔲 Comandos de Stack

### update
Descargar las últimas imágenes de un stack y recrear sus containers

```bash
hms update media
hms update infra
hms update media,necesse   # Múltiples stacks
hms update                 # Todos los stacks habilitados
```

Si el stack está parado, descarga las imágenes pero no lo levanta.

### up
Levantar stack(s)

```bash
hms up infra
hms up infra,media
hms up                 # Levantar solo stacks habilitados
```

### down
Detener stack(s)

```bash
hms down infra
hms down media,necesse
hms down               # Detener todos los stacks
```

### restart
Reiniciar stack(s)

```bash
hms restart infra
hms restart            # Reiniciar solo stacks habilitados
```

### info
Información del stack

```bash
hms info infra
hms info               # Info de todos los stacks habilitados
```

### validate
Validar configuración

```bash
hms validate infra
hms validate           # Validar todos los stacks habilitados
```

### logs
Ver logs del stack

```bash
hms logs infra
hms logs infra -f
hms logs infra -f --tail 100
hms logs infra traefik -f
hms logs infra --timestamps
hms logs infra --since 10m
hms logs infra --until 2h
```

## 🔌 Ejemplos

### Instalación Inicial

```bash
hms install
hms start
hms list
hms up infra
hms info infra
hms logs infra -f
```

### Gestión de Stacks

```bash
# Levantar múltiples stacks
hms up infra
hms up media
hms up necesse

# Reiniciar un stack
hms restart infra

# Ver estado
hms info infra
hms info media
```

### Backups

```bash
# Crear backup de todos los stacks
hms system backup

# Backup de stack específico
hms system backup --stack media

# Listar backups
hms system backup list

# Restaurar backup
hms system backup restore --file hms_20240219-143000.tar.gz
```

### Troubleshooting

```bash
hms logs infra
hms logs infra -f
hms validate infra
hms restart infra
```

### Actualización del Sistema

```bash
# Actualizar imágenes Docker de un stack
hms update media
hms update infra

# Actualizar todos los stacks (excepto infra)
hms system update-stacks

# Actualizar solo infra
hms system update-infra

# Actualizar HMS desde el repositorio
hms self-update

# Actualizar DNS de Cloudflare
hms system update-dns
hms system update-dns --ip 1.2.3.4
hms system update-dns --list
hms system update-dns --dry-run
```
