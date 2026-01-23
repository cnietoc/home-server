# Core - Componentes Core del Home Server

Este directorio contiene los componentes core del sistema que no son aplicaciones de usuario sino infraestructura esencial.

## Estructura

```
core/
├── hms/                # Contenedor del CLI Python
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── ...
└── infra/              # Infraestructura base
    ├── docker-compose.yml
    ├── stack.yml
    ├── pre-deploy.py
    └── traefik/
```

## Componentes

### hms/
El contenedor Docker que ejecuta el CLI HMS en Python. Este es el cerebro del sistema que gestiona todos los demás stacks.

**Servicios:**
- CLI HMS en contenedor con acceso a docker.sock

**Deploy:**
```bash
cd core/hms && docker compose up -d
```

### infra/
La infraestructura base del servidor que debe estar siempre corriendo.

**Servicios:**
- **Traefik**: Proxy inverso con SSL automático
- **TinyAuth**: Autenticación centralizada con Google OAuth
- **Watchtower**: Actualizaciones automáticas de contenedores
- **Samba**: Servidor de archivos CIFS/SMB

**Deploy:**
```bash
hms infra up
```

## Diferencia con stacks/

Los componentes en `core/` son:
- Esenciales para el funcionamiento del sistema
- Gestionados de forma especial por HMS
- Generalmente deployados primero antes que otros stacks

Los stacks en `stacks/` son:
- Aplicaciones de usuario
- Opcionales y independientes entre sí
- Auto-descubiertos por HMS

