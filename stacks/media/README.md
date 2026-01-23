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
- **qBittorrent** (`qbittorrent.tu-dominio.com`) 🔒 - Cliente BitTorrent moderno
  - Web UI nativa y moderna
  - Categories automáticas para organización
  - Mejor integración con *arr apps
  - RSS feeds integrados
  
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
├── library/             # Biblioteca única de películas y series
│   ├── movies/          # Películas
│   └── tv/              # Series
├── downloads/           # Gestión de descargas
│   ├── complete/        # Descargas completadas
│   ├── incomplete/      # Descargas en progreso
│   └── watch/           # Carpeta watch para torrents
└── config/              # Configuraciones de servicios
    ├── jellyfin/        # Configuración Jellyfin
    ├── radarr/          # Configuración Radarr
    ├── sonarr/          # Configuración Sonarr
    ├── qbittorrent/     # Configuración qBittorrent
    ├── prowlarr/        # Configuración Prowlarr
    ├── tdarr/           # Configuración Tdarr
        ├── server/      # Configuración servidor Tdarr
        └── logs/        # Logs de Tdarr
```

## 🔧 Configuración Inicial

### 1. Configurar Variables (Opcional)
La mayoría de configuraciones están predefinidas en `docker-compose.yml`. Solo necesitas editar `config/private/media.env` para:

```bash
# Credenciales de qBittorrent (cambiar por seguridad)
QBITTORRENT_USER=admin
QBITTORRENT_PASS=adminadmin

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

### 💬 **1. Configurar qBittorrent (PRIMERO - Obligatorio)**

**⚠️ IMPORTANTE: Configurar qBittorrent ANTES que cualquier otro servicio.**

#### **Paso 1: Obtener contraseña temporal**
1. **Desplegar el stack**: `./scripts/deploy.sh media`
2. **Ver los logs del contenedor** para obtener la contraseña temporal:
   ```bash
   docker logs media_qbittorrent
   ```
3. **Buscar este mensaje** en los logs:
   ```
   ******** Information ********
   To control qBittorrent, access the WebUI at: http://localhost:8080
   The WebUI administrator username is: admin
   The WebUI administrator password was not set. A temporary password is provided for this session: kATnHVjTM
   You should set your own password in program preferences.
   ```
4. **Anotar la contraseña temporal** (ejemplo: `kATnHVjTM`)

#### **Paso 2: Primer acceso y configuración**
1. **Accede a** `https://qbittorrent.tu-dominio.com`
2. **Login inicial:**
   - Usuario: `admin`
   - Contraseña: `[contraseña temporal de los logs]`
3. **¡OBLIGATORIO! Cambiar credenciales inmediatamente:**
   - Tools → Preferences → Web UI
   - Username: Cambiar por uno seguro
   - Password: Cambiar por una contraseña segura y **apuntarla**
   - **Apply** y **OK**

#### **Paso 3: Configurar paths de descarga**
4. **Settings → Downloads:**
   - Default Save Path: `/media/downloads/complete`
   - Keep incomplete torrents in: `/media/downloads/incomplete`
   - Copy .torrent files to: `/media/downloads/torrents`
   - Keep incomplete torrents: ✅
5. **Settings → BitTorrent:**
   - Enable DHT: ✅
   - Enable PeX: ✅
   - Enable LSD: ✅

#### **Paso 4: Apuntar las credenciales finales**
**📝 Importante:** Apunta las credenciales que configuraste porque las necesitarás para Radarr y Sonarr:
- Usuario: `[el que configuraste]`
- Contraseña: `[la que configuraste]`

### 🎥 **2. Configurar Radarr**
1. Accede a `https://radarr.tu-dominio.com`
2. **Settings → General:**
   - Copia la **API Key** (necesaria para Prowlarr)
3. **Settings → Media Management:**
   - Root Folder: `/media/library/movies`
   - Rename Movies: ✅
   - File Management: Create empty movie folders ✅
4. **Settings → Download Clients:**
   - Add → qBittorrent:
     - Host: `qbittorrent`
     - Port: `8080`
     - Username: `[el que configuraste en qBittorrent]`
     - Password: `[la que configuraste en qBittorrent]`
     - Category: `movies`
   - Remote Path Mappings:
     - Remote Path: `/media/downloads`
     - Local Path: `/media/downloads`
5. **Settings → Indexers:**
   - Los indexadores aparecerán **después** de configurar Prowlarr y hacer sync

### 📺 **3. Configurar Sonarr**
1. Accede a `https://sonarr.tu-dominio.com`
2. **Settings → General:**
   - Copia la **API Key** (necesaria para Prowlarr)
3. **Settings → Media Management:**
   - Root Folder: `/media/library/tv`
   - Rename Episodes: ✅
   - Episode Naming: Standard Episode Format
4. **Settings → Download Clients:**
   - Add → qBittorrent:
     - Host: `qbittorrent`
     - Port: `8080`
     - Username: `[el que configuraste en qBittorrent]`
     - Password: `[la que configuraste en qBittorrent]`
     - Category: `tv`
   - Remote Path Mappings:
     - Remote Path: `/media/downloads`
     - Local Path: `/media/downloads`
5. **Settings → Indexers:**
   - Los indexadores aparecerán **después** de configurar Prowlarr y hacer sync

### 🔗 **4. Configurar Prowlarr**
1. Accede a `https://prowlarr.tu-dominio.com`
2. **Settings → General:** Copia la **API Key** (necesaria para conectar con Radarr/Sonarr)
3. **Indexers:** Agrega indexadores manualmente:
   - Add Indexer → The Pirate Bay
   - Add Indexer → 1337x
   - Add Indexer → YTS, etc.
4. **Settings → Apps:** Configura conexiones a Radarr/Sonarr:
   - **Add Application → Radarr:**
     - Prowlarr Server: `http://prowlarr:9696`
     - Radarr Server: `http://radarr:7878`
     - API Key: (copiar desde Radarr → Settings → General)
   - **Add Application → Sonarr:**
     - Prowlarr Server: `http://prowlarr:9696`
     - Sonarr Server: `http://sonarr:8989`
     - API Key: (copiar desde Sonarr → Settings → General)
5. **Sync App Indexers:** Esto enviará los indexadores configurados a Radarr/Sonarr automáticamente
6. **Settings → Download Clients (Opcional):**
   - FlareSolverr: `http://flaresolverr:8191` (para sitios con CloudFlare)

### 🔗 **4b. Configurar Jackett (Complementario)**
1. Accede a `https://jackett.tu-dominio.com`
2. Agrega trackers específicos que Prowlarr no tenga o trackers privados
3. Configura FlareSolverr: `http://flaresolverr:8191`
4. Copia la **API Key** de Jackett 
5. **En Prowlarr:** **Settings → Indexers → Add Indexer → Torznab (Custom)**
   - Name: Jackett - [nombre del tracker]
   - URL: `http://jackett:9117/api/v2.0/indexers/[indexer-id]/results/torznab/`
   - API Key: [Tu API Key de Jackett]
   - Categories: 2000,5000,7000 (Movies, TV, Other)
6. **Test** la conexión y **Save**
7. Los indexadores de Jackett aparecerán como disponibles en Prowlarr

### 🔄 **5. Configurar Tdarr**
1. Accede a `https://tdarr.tu-dominio.com`
2. **Libraries:** Agrega las rutas de medios:
   - `/media/library/movies` para películas
   - `/media/library/tv` para series
3. **Plugins:** Configura para tu hardware y preferencias
4. **Ejemplo para H.264 1080p:**
   - Input: Cualquier formato
   - Output: H.264, 1080p, ~5Mbps
   - Tempdir: `/temp` (ya configurado)
5. **Configuración importante:**
   - Configura Tdarr para reemplazar archivos originales tras optimizar
   - Mantiene una sola versión del archivo (optimizada)

### 📺 **6. Configurar Jellyfin (Reproducción Directa)**
1. Accede a `https://jellyfin.tu-dominio.com`
2. **Configuración → Bibliotecas:**
   - Agrega `/media/library/movies` para películas
   - Agrega `/media/library/tv` para series
   - Agrega `/media/library/music` para música (opcional)
3. **Configuración → Reproducción:**
   - ✅ Habilitar reproducción directa de video
   - ✅ Habilitar reproducción directa de audio
   - ❌ Deshabilitar transcodificación de hardware
   - ❌ Deshabilitar transcodificación de software
4. **Configuración → Usuarios:**
   - Para cada usuario: **Reproducción → Permitir reproducción directa**
5. **Resultado:** Jellyfin reproduce archivos optimizados por Tdarr para máxima compatibilidad

## 🎯 Flujo de Trabajo Optimizado

### **Orden de configuración correcto:**
1. **Primero**: Desplegar el stack completo con `./scripts/deploy.sh media`
2. **Segundo**: Configurar qBittorrent (obtener contraseña temporal desde logs)
3. **Tercero**: Configurar Radarr y Sonarr (con las credenciales de qBittorrent)
4. **Cuarto**: Configurar Prowlarr con las API Keys de Radarr/Sonarr
5. **Quinto**: Prowlarr sincroniza indexadores a Radarr/Sonarr automáticamente
6. **Opcional**: Configurar Jackett para trackers adicionales

### **Pipeline de procesamiento:**
1. **Descarga**: Radarr/Sonarr → Prowlarr → Indexadores → qBittorrent
2. **Organización**: Sonarr/Radarr mueven archivos completados a `library`
3. **Transcodificación**: Tdarr procesa archivos en `library` y los reemplaza optimizados
4. **Reproducción**: Jellyfin sirve contenido optimizado desde `library`

### **Ventajas de esta configuración:**
- **🚀 Jellyfin sin carga**: Solo reproduce, no transcodifica
- **⚡ Reproducción inmediata**: Videos pre-optimizados por Tdarr
- **🔧 Hardware eficiente**: Solo Tdarr usa aceleración por hardware
- **📱 Compatible universal**: Videos optimizados para todos los dispositivos
- **💾 Gestión eficiente**: Una sola versión optimizada por archivo
- **🎛️ Gestión simple**: Un solo directorio de medios para mantener
- **🔗 Configuración centralizada**: Prowlarr gestiona todos los indexadores

### **Configuración de Tdarr:**
- Procesa automáticamente archivos nuevos en la librería `library`
- Convierte a formatos compatibles reemplazando los originales
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
```

## 🚨 Solución de Problemas Comunes

### **❌ "No veo indexadores en Radarr/Sonarr"**
**Causa**: Prowlarr NO configura automáticamente los indexadores en Radarr/Sonarr.

**Solución**:
1. Primero configura Radarr/Sonarr completamente
2. Copia las API Keys de ambos servicios
3. En Prowlarr → Settings → Apps → Add Application
4. Configura las conexiones a Radarr y Sonarr con sus API Keys
5. Haz clic en "Sync App Indexers" para enviar los indexadores

### **❌ "qBittorrent no descarga archivos"**
**Causa**: Path mappings incorrectos entre servicios o configuración de usuario incorrecta.

**Solución**:
- Verificar que todos los servicios usan `/media/downloads` como directorio
- En Radarr/Sonarr: Settings → Download Clients → Remote Path Mappings
- Remote Path: `/media/downloads` → Local Path: `/media/downloads`
- Verificar credenciales de qBittorrent (admin/adminadmin por defecto)

### **❌ "Tdarr no procesa archivos"**
**Causa**: Configuración de bibliotecas incorrecta.

**Solución**:
1. Tdarr → Libraries → Add Library
2. Source: `/media/library` (directorio completo)
3. Cache: `/cache`
4. Output: Reemplazar archivos originales
5. Transcode cache: `/transcode_cache`

### **❌ "Jellyfin no encuentra archivos"**
**Causa**: Bibliotecas no configuradas correctamente.

**Solución**:
1. Jellyfin → Dashboard → Libraries → Add Library
2. Movies: `/media/library/movies`
3. TV Shows: `/media/library/tv`
4. Enable real-time monitoring

### **❌ "Prowlarr no se conecta a Jackett"**
**Causa**: URL o API Key incorrectos.

**Solución**:
1. En Jackett, verifica que el indexer esté funcionando
2. Copia la URL específica del indexer (no la URL base de Jackett)
3. En Prowlarr: Add Indexer → Torznab Custom
4. URL completa: `http://jackett:9117/api/v2.0/indexers/[indexer-id]/results/torznab/`

## 🔄 Actualizaciones

El stack usa Watchtower para actualizaciones automáticas de imágenes oficiales. Las configuraciones se preservan en volúmenes persistentes.
