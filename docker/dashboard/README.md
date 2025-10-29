# 🏠 Home Server Dashboard (ServerInfo Stack)

Dashboard dinámico del Home Server que muestra información en tiempo real del servidor y servicios disponibles.

## 🚀 Características

- **📊 Información en tiempo real**: Calcula toda la información al momento de la consulta
- **🖥️ Datos del sistema**: Hostname, uptime, memoria, disco
- **🐳 Estado de Docker**: Contenedores totales y en ejecución
- **📦 Stacks y servicios**: Lista dinámica con URLs funcionales
- **🌐 Sin subdominio**: Se abre directamente en el dominio principal
- **♻️ Auto-actualización**: Refresco automático cada 30 segundos

## 🛠️ Tecnologías

- **Node.js 18** con Express
- **YAML parser** para leer configuración de stacks
- **Docker CLI** para obtener información de contenedores
- **Comandos del sistema** para estadísticas del servidor

## 📡 API Endpoints

- `GET /` - Dashboard web principal
- `GET /api/system` - Información del sistema
- `GET /api/stacks` - Stacks y servicios configurados
- `GET /api/dashboard` - Datos completos del dashboard

## 🔧 Configuración

El servicio lee automáticamente:
- `/config/stacks.yml` - Configuración de stacks y servicios
- Variables de entorno desde `common.env`
- Información del sistema en tiempo real

## 📦 Despliegue

```bash
# Generar archivos .env
./scripts/generate-docker-envs.sh serverinfo

# Desplegar el stack
./scripts/deploy.sh serverinfo
```

## 🌐 Acceso

Una vez desplegado, el dashboard estará disponible en:
- **URL**: https://tu-dominio.com (dominio principal, sin subdominio)
- **Puerto interno**: 3000
- **Red**: Conectado a la red de Traefik

## 🔍 Características técnicas

- **Contenedor ligero**: Alpine Linux con Node.js
- **Acceso Docker**: Socket montado para consultar contenedores
- **Sistema de archivos**: Acceso de solo lectura a /proc y /sys
- **Seguridad**: Usuario no-root dentro del contenedor
- **Reinicio automático**: `unless-stopped`

## 📋 Datos mostrados

### Sistema
- Hostname del servidor
- Tiempo de actividad (uptime)
- Uso de memoria (total/usado/disponible)
- Uso de disco (total/usado/disponible/porcentaje)

### Docker
- Total de contenedores
- Contenedores en ejecución

### Stacks y Servicios
- Lista dinámica de todos los stacks configurados
- Servicios con sus URLs funcionales
- Indicadores de protección
- Enlaces directos a cada servicio

## 🔄 Actualización automática

El dashboard se actualiza automáticamente:
- **Frontend**: Cada 30 segundos
- **Backend**: En cada consulta (tiempo real)
- **Caché**: Sin caché, datos siempre frescos
