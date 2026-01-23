# Stacks - Aplicaciones del Home Server

Este directorio contiene todos los stacks de aplicación del home server. Cada stack es una aplicación o servicio independiente que se puede deployar por separado.

## Estructura de un Stack

Cada stack debe tener:

```
stacks/nombre-stack/
├── docker-compose.yml    # Definición de servicios Docker (REQUERIDO)
├── stack.yml             # Metadata del stack (REQUERIDO)
├── pre-deploy.sh         # Script pre-deploy opcional
├── pre-deploy.py         # Script pre-deploy Python opcional
└── ...                   # Otros archivos del stack
```

## stack.yml

El archivo `stack.yml` contiene la metadata de orquestación del stack:

- **description**: Descripción del stack
- **config_files**: Lista de archivos .env a incluir (además de common.env)
- **services**: Servicios expuestos con subdominios y protección
- **shares**: Carpetas compartidas via Samba (opcional)
- **backups**: Exclusiones de backup (opcional)

Ver `config/templates/stack.yml.template` para un ejemplo completo.

## Añadir un Nuevo Stack

1. Crear directorio en `stacks/nuevo-stack/`
2. Crear `docker-compose.yml` con los servicios
3. Crear `stack.yml` con la metadata (usa el template)
4. El stack será auto-descubierto por HMS

## Stacks Disponibles

- **home**: Dashboard del Home Server
- **media**: Suite de medios (Jellyfin, Radarr, Sonarr, etc.)
- **steam**: ArchiSteamFarm para farmeo de cromos
- **necesse**: Servidor de juego Necesse
- **helloworld**: Stack de ejemplo/prueba
- **zomboid**: Servidor de Project Zomboid

## Deploy de Stacks

```bash
# Ver todos los stacks disponibles
hms list

# Deploy de un stack específico
hms media up

# Ver estado de un stack
hms media status

# Detener un stack
hms media down
```

