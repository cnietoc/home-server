# 🎬 Media Stack - Suite Completa de Entretenimiento

Stack completo para gestión, descarga y streaming de contenido multimedia. Incluye gestión automatizada de películas, series, subtítulos y transcodificación.

## 🚀 Servicios Incluidos

### 📺 **Streaming y Reproducción**
- **Jellyfin** (`jellyfin.tu-dominio.com`) - Servidor de medios principal
  - Streaming de películas, series, música y fotos
  - Apps para TV, móvil, navegador
  - Transcodificación automática
  - Soporte para múltiples usuarios

### ⬇️ **Gestión de Descargas**
- **Transmission** (`transmission.tu-dominio.com`) 🔒 - Cliente BitTorrent
  - Descargas automáticas vía torrent
  - Interfaz web completa
  - Programación de velocidades
  
- **Prowlarr** (`prowlarr.tu-dominio.com`) 🔒 - Indexador universal
  - Centraliza indexadores de torrents
  - Integración automática con Radarr/Sonarr
  - Punto central de configuración

- **Jackett** (`jackett.tu-dominio.com`) 🔒 - Agregador complementario
  - Soporte para trackers que Prowlarr no tiene
  - Integración vía Torznab con Prowlarr
  - Acceso a trackers privados específicos

### 🎥 **Gestión de Contenido**
- **Radarr** (`radarr.tu-dominio.com`) 🔒 - Películas
  - Búsqueda automática de películas
  - Gestión de calidades y formatos
  - Monitoreo de lanzamientos

- **Sonarr** (`sonarr.tu-dominio.com`) 🔒 - Series de TV
  - Seguimiento automático de series
  - Descarga de episodios nuevos
  - Gestión de temporadas completas

- **Bazarr** (`bazarr.tu-dominio.com`) 🔒 - Subtítulos
  - Descarga automática de subtítulos
  - Múltiples idiomas
  - Integración con Radarr/Sonarr

### 🔄 **Procesamiento**
- **Tdarr** (`tdarr.tu-dominio.com`) 🔒 - Transcodificación
  - Convierte videos a formatos optimizados
  - Reduce tamaño de archivos
  - Compatibilidad con TV/dispositivos
  - Soporte para aceleración por hardware

- **FlareSolverr** (interno) - Resuelve challenges de CloudFlare

## 📁 Estructura de Directorios

```
data/media/              # Todo centralizado en el stack media
├── library-raw/        # Biblioteca original gestionada por Sonarr/Radarr
│   ├── movies/         # Películas originales
│   └── tv/             # Series originales
├── library-optimized/  # Biblioteca optimizada por Tdarr (para Jellyfin)
│   ├── movies/         # Películas optimizadas
│   └── tv/             # Series optimizadas
├── downloads/           # Gestión de descargas
│   ├── complete/        # Descargas completadas
│   ├── incomplete/      # Descargas en progreso
│   └── watch/           # Carpeta watch para torrents
└── config/              # Configuraciones de servicios
    ├── jellyfin/        # Configuración Jellyfin
    ├── radarr/          # Configuración Radarr
    ├── sonarr/          # Configuración Sonarr
    ├── transmission/    # Configuración Transmission
    ├── prowlarr/        # Configuración Prowlarr
    ├── bazarr/          # Configuración Bazarr
    └── tdarr/           # Configuración Tdarr
        ├── server/      # Configuración servidor Tdarr
        └── logs/        # Logs de Tdarr
```

## 🔧 Configuración Inicial

### 1. Configurar Variables (Opcional)
La mayoría de configuraciones están predefinidas en `docker-compose.yml`. Solo necesitas editar `config/private/media.env` para:

```bash
# Credenciales de Transmission (cambiar por seguridad)
TRANSMISSION_USER=tu_usuario
TRANSMISSION_PASS=tu_password_seguro

# Aceleración por hardware (si tienes GPU compatible)
ENABLE_INTEL_QSV=false   # Intel Quick Sync Video
ENABLE_NVIDIA=false      # NVIDIA NVENC
ENABLE_VAAPI=false       # AMD VAAPI

# Configuración de transcodificación Tdarr
PREFERRED_CODEC=h264     # h264, h265, av1
TARGET_RESOLUTION=1080p  # 720p, 1080p, 4k
TARGET_BITRATE=5000k     # Bitrate objetivo
```

**Estructura de directorios:** Todo está centralizado en `data/media/` y se configura automáticamente.

### 2. Desplegar Stack
```bash
# Generar archivos .env
./scripts/generate-docker-envs.sh media

# Desplegar todos los servicios
./scripts/deploy.sh media
```

**Nota:** La estructura de directorios se crea automáticamente con `.gitkeep` files que mantienen la organización en el repositorio.

## ⚙️ Configuración de Servicios

### 🔗 **1. Configurar Prowlarr (Primero)**
1. Accede a `https://prowlarr.tu-dominio.com`
2. Agrega indexadores (The Pirate Bay, 1337x, etc.)
3. Configura FlareSolverr: `http://flaresolverr:8191`

### 🔗 **1b. Configurar Jackett (Complementario)**
1. Accede a `https://jackett.tu-dominio.com`
2. Agrega trackers específicos que Prowlarr no tenga
3. Configura FlareSolverr: `http://flaresolverr:8191`
4. Copia la **API Key** de Jackett 
5. En Prowlarr: **Settings > Indexers > Add Indexer > Torznab**
   - URL: `http://jackett:9117/api/v2.0/indexers/[indexer-id]/results/torznab/`
   - API Key: [Tu API Key de Jackett]
   - Categories: 2000,5000,7000 (Movies, TV, Other)
6. **Opcional**: Jackett puede descargar .torrents directamente al watch folder de Transmission

### 🎥 **2. Configurar Radarr**
1. Accede a `https://radarr.tu-dominio.com`
2. **Settings → Media Management:**
   - Root Folder: `/movies`
   - Rename Movies: ✅
3. **Settings → Download Clients:**
   - Add Transmission: `http://transmission:9091`
   - Remote Path: `/downloads` → Local Path: `/downloads`
4. **Settings → Indexers:**
   - Sync automático desde Prowlarr

### 📺 **3. Configurar Sonarr**
1. Accede a `https://sonarr.tu-dominio.com`
2. **Settings → Media Management:**
   - Root Folder: `/tv`
   - Rename Episodes: ✅
3. **Settings → Download Clients:**
   - Add Transmission: `http://transmission:9091`
   - Remote Path: `/downloads` → Local Path: `/downloads`
4. **Settings → Indexers:**
   - Sync automático desde Prowlarr

### 💬 **4. Configurar Bazarr**
1. Accede a `https://bazarr.tu-dominio.com`
2. **Settings → Sonarr:**
   - URL: `http://sonarr:8989`
   - API Key: (copiar desde Sonarr)
3. **Settings → Radarr:**
   - URL: `http://radarr:7878`
   - API Key: (copiar desde Radarr)

### 🔄 **5. Configurar Tdarr**
1. Accede a `https://tdarr.tu-dominio.com`
2. **Libraries:** Agrega las rutas de medios:
   - `/input/movies` para películas originales (`library-raw`)
   - `/input/tv` para series originales (`library-raw`)
   - `/output/movies` para películas optimizadas (`library-optimized`)
   - `/output/tv` para series optimizadas (`library-optimized`)
3. **Plugins:** Configura para tu hardware y preferencias
4. **Ejemplo para H.264 1080p:**
   - Input: Cualquier formato
   - Output: H.264, 1080p, ~5Mbps
   - Tempdir: `/temp` (ya configurado)

### 📺 **6. Configurar Jellyfin (Reproducción Directa)**
1. Accede a `https://jellyfin.tu-dominio.com`
2. **Configuración → Bibliotecas:**
   - Agrega `/media/movies` y `/media/tv` apuntando a `library-optimized` como principal
   - Opcional: Agrega también `/media-raw/movies` y `/media-raw/tv` para acceso secundario a la original
3. **Configuración → Reproducción:**
   - ✅ Habilitar reproducción directa de video
   - ✅ Habilitar reproducción directa de audio
   - ❌ Deshabilitar transcodificación de hardware
   - ❌ Deshabilitar transcodificación de software
4. **Configuración → Usuarios:**
   - Para cada usuario: **Reproducción → Permitir reproducción directa**
5. **Resultado:** Jellyfin solo reproduce archivos optimizados por Tdarr, pero puedes acceder a los originales si lo necesitas

## 🎯 Flujo de Trabajo Optimizado

### **Pipeline de Procesamiento:**
1. **Descarga**: Radarr/Sonarr → Prowlarr → Transmission
2. **Organización**: Sonarr/Radarr mueven archivos a `library-raw`
3. **Transcodificación**: Tdarr procesa desde `library-raw` y deja los optimizados en `library-optimized`
4. **Subtítulos**: Bazarr descarga subtítulos
5. **Reproducción**: Jellyfin sirve contenido desde `library-optimized` (y opcionalmente desde la original)

### **Ventajas de esta configuración:**
- **🚀 Jellyfin sin carga**: Solo reproduce, no transcodifica
- **⚡ Reproducción inmediata**: Videos pre-optimizados por Tdarr
- **🔧 Hardware eficiente**: Solo Tdarr usa aceleración por hardware
- **📱 Compatible universal**: Videos optimizados para todos los dispositivos
- **💾 Gestión de almacenamiento**: Mantienes originales y optimizados separados
- **🔙 Recuperación fácil**: Siempre tienes acceso a los originales (`library-raw`)

### **Configuración de Tdarr:**
- Procesa automáticamente archivos nuevos desde la librería `library-raw`
- Convierte a formatos compatibles y deja los resultados en la optimizada
- Mantiene calidad optimizando bitrate
- Usa hardware acceleration cuando está disponible

## 🔒 Seguridad y Acceso

- **Públicos:** Solo Jellyfin (para familia/amigos)
- **Protegidos:** Todos los servicios de gestión (requieren autenticación)
- **Red interna:** Comunicación segura entre servicios
- **Puertos externos:** Solo los necesarios para torrents

## 🚀 Optimizaciones

### Hardware Acceleration (Solo Tdarr)
Para acelerar la transcodificación en Tdarr, edita las variables en `config/private/media.env`:

**Intel Quick Sync Video:**
```bash
ENABLE_INTEL_QSV=true
```

**NVIDIA NVENC:**
```bash
ENABLE_NVIDIA=true
```

**AMD VAAPI:**
```bash
ENABLE_VAAPI=true
```

**Configuración automática:**
- Al ejecutar `./scripts/deploy.sh media`, se ejecuta automáticamente `docker/media/pre-deploy.sh`
- Genera un `docker-compose.override.yml` con la configuración de hardware
- Solo afecta a **Tdarr** - Jellyfin permanece sin transcodificación
- Este archivo configura la aceleración por hardware según las variables de entorno
- No necesitas modificar manualmente el `docker-compose.yml`
- Los archivos generados se ignoran en git para evitar conflictos

**Importante:** Jellyfin está configurado para reproducción directa únicamente. Toda la transcodificación la realiza Tdarr de forma previa.

### Almacenamiento
- **SSD:** Para configuraciones y base de datos
- **HDD:** Para almacenamiento de medios
- **NFS/SMB:** Para almacenamiento en red

## 📊 Monitoreo

Todos los servicios se muestran en el Home Dashboard:
- Estado de contenedores
- Acceso rápido a interfaces web
- Separación clara entre servicios públicos y administrativos

## 🆘 Troubleshooting

**Problemas comunes:**
- **Permisos:** Verificar PUID/PGID correctos
- **Rutas:** Asegurar que todas las rutas existan
- **Red:** Verificar conectividad entre servicios
- **Espacio:** Monitorear espacio en disco

**Logs útiles:**
```bash
docker logs media_jellyfin
docker logs media_radarr
docker logs media_transmission
```

## 🔄 Actualizaciones

El stack usa Watchtower para actualizaciones automáticas de imágenes oficiales. Las configuraciones se preservan en volúmenes persistentes.
