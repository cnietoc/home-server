# Referencia de Comandos CLI - HMS

Guía completa de todos los comandos disponibles en HMS.

## 📋 Estructura General de Comandos

```
hms [stack...] <comando> [argumentos]
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

### update
Actualizar HMS desde el repositorio

```bash
hms update
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

### up
Levantar stack(s)

```bash
hms infra up
hms infra,media up
hms up                 # Levantar solo stacks habilitados
```

### down
Detener stack(s)

```bash
hms infra down
hms media,necesse down
hms down               # Detener todos los stacks
```

### restart
Reiniciar stack(s)

```bash
hms infra restart
hms restart            # Reiniciar solo stacks habilitados
```

### info
Información del stack

```bash
hms infra info
hms info               # Info de todos los stacks habilitados
```

### validate
Validar configuración

```bash
hms infra validate
hms validate           # Validar todos los stacks habilitados
```

### logs
Ver logs del stack

```bash
hms infra logs
hms infra logs -f
hms infra logs -f --tail 100
hms infra logs traefik -f
hms infra logs --timestamps
hms infra logs --since 10m
hms infra logs --until 2h
```

## 🔌 Ejemplos

### Instalación Inicial

```bash
hms install
hms start
hms list
hms infra up
hms infra info
hms infra logs -f
```

### Gestión de Stacks

```bash
# Levantar múltiples stacks
hms infra up
hms media up
hms necesse up

# Reiniciar un stack
hms infra restart

# Ver estado
hms infra info
hms media info
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
hms infra logs
hms infra logs -f
hms infra validate
hms infra restart
```

### Actualización del Sistema

```bash
# Actualizar HMS
hms update

# Actualizar DNS de Cloudflare
hms system update-dns
hms system update-dns --ip 1.2.3.4
hms system update-dns --list
hms system update-dns --dry-run
```
