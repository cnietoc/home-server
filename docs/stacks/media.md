# Stack: Media (Gestión Multimedia)
Stack para gestión y streaming de contenido multimedia.
## 📋 Overview
| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 8 servicios (Jellyfin, qBittorrent, Radarr, Sonarr, Prowlarr, Tdarr, Jackett, FlareSolverr) |
| **Puertos Expuestos** | 8096 (Jellyfin - opcional), 6881 (qBittorrent - torrent) |
| **Almacenamiento** | Depende contenido (100GB+) |
## 🎬 Servicios Incluidos

### 1. Jellyfin - Servidor Multimedia
Servidor de streaming de películas, series, música y fotos
- **URL**: `https://jellyfin.{DOMAIN}`
- **Protegido**: ❌ No (autenticación propia)
- **Función**: Streaming de contenido multimedia, transcodificación, subtítulos, múltiples usuarios

### 2. qBittorrent - Cliente BitTorrent
Cliente de descargas por BitTorrent
- **URL**: `https://qbittorrent.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Descarga de torrents, integración con Radarr/Sonarr

### 3. Radarr - Gestor de Películas
Descarga y organización automática de películas
- **URL**: `https://radarr.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Búsqueda automática, descarga y organización de películas

### 4. Sonarr - Gestor de Series
Descarga y organización automática de series TV
- **URL**: `https://sonarr.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Seguimiento de series, descarga automática de episodios nuevos

### 5. Prowlarr - Indexador
Indexador centralizado para Radarr y Sonarr
- **URL**: `https://prowlarr.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Gestión centralizada de indexadores/trackers

### 6. Tdarr - Transcodificador
Transcodificación y optimización automática de video
- **URL**: `https://tdarr.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Conversión automática de formatos, compresión, optimización

### 7. Jackett - Agregador de Trackers
Agregador de trackers complementario a Prowlarr
- **URL**: `https://jackett.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Acceso a trackers adicionales

### 8. FlareSolverr - Resolvedor CloudFlare
Servicio interno para resolver desafíos CloudFlare
- **URL**: Sin acceso web (servicio interno)
- **Protegido**: N/A (solo red interna)
- **Función**: Resolver CAPTCHAs y desafíos CloudFlare para Prowlarr
## 📋 Configuración Requerida

> Este stack no requiere configuración específica en `config.toml`. Solo necesita la configuración global del sistema.

### 🔧 Configuración Opcional

Estas opciones están disponibles en `config.default.toml` y pueden modificarse en tu `config.toml`:

```toml
# Aceleración hardware para transcodificación (por defecto: desactivado)
[media]
enable_intel_qsv = false   # true = Activar Intel Quick Sync Video
enable_nvidia = false      # true = Activar NVIDIA GPU
enable_vaapi = false       # true = Activar VAAPI (Intel/AMD)

# Exclusiones de backup (por defecto: excluye archivos grandes)
[media.backups]
exclude = [
    "/library",            # Biblioteca de medios (muy grande)
    "/downloads",          # Descargas temporales
    "/recordings",         # Grabaciones de TV
    "/config/tdarr/server/Tdarr/Samples/",
    "/config/tdarr/server/Tdarr/DB2/JobReports/",
    "/config/tdarr/server/Tdarr/Backups/",
    "/config/qbittorrent/data/BT_backup/",
    "/config/prowlarr/Backups/",
    "/config/radarr/Backups/",
    "/config/sonarr/logs/",
    "/config/sonarr/Backups",
    "/config/jackett/*.txt",
    "/config/jellyfin/log/",
    "/config/jellyfin/temp/"
]
```

> **💡 Nota**: La configuración de API keys, indexadores y trackers se realiza directamente en las interfaces web de cada servicio tras el primer despliegue.
## 📁 Estructura de Datos

```
data/media/
├── library/
│   ├── movies/              # Películas organizadas
│   └── tv/                  # Series organizadas
├── downloads/
│   ├── incomplete/          # En proceso
│   ├── complete/            # Completadas
│   └── watch/               # Carpeta para archivos .torrent
├── recordings/              # Grabaciones (TV en vivo)
└── config/
    ├── jellyfin/            # Configuración Jellyfin
    ├── qbittorrent/         # Configuración qBittorrent
    ├── radarr/              # Configuración Radarr
    ├── sonarr/              # Configuración Sonarr
    ├── prowlarr/            # Configuración Prowlarr
    ├── tdarr/               # Configuración Tdarr
    ├── jackett/             # Configuración Jackett
    └── flaresolverr/        # Configuración FlareSolverr
```
## 🚀 Primeros Pasos
```bash
# 1. Configurar en config.toml
# 2. Validar
hms validate media
# 3. Levantar
hms up media
# 4. Esperar (puede tomar 1-2 minutos)
sleep 60
# 5. Acceder a Jellyfin
# https://jellyfin.ejemplo.com
# Usuario: admin (crear contraseña primera vez)
# 6. Configurar librerías en Jellyfin
# - Añadir carpetas: /data/media/library/...
```
## 🎯 Workflow Típico
1. **Agregar película/serie deseada**:
   - Radarr: Movies → Add New → Buscar → Add
   - Sonarr: Series → Add New → Buscar → Add
2. **Radarr/Sonarr buscan**:
   - Buscan en indexadores configurados vía Prowlarr
   - Si existe: automáticamente envían a qBittorrent
3. **qBittorrent descarga**:
   - Guarda en downloads/
   - Notifica a Radarr/Sonarr cuando termina
4. **Radarr/Sonarr organizan**:
   - Mueven a library/movies/ o library/tv/
   - Renombran según convención
5. **Jellyfin indexa**:
   - Detecta nuevo contenido
   - Lo hace disponible en interfaz
6. **Usuario disfruta**:
   - Streaming desde Jellyfin
   - Múltiples dispositivos
   - Subtítulos, calidad adaptable
