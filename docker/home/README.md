# 🏠 Home Server Dashboard (Home Stack)

Dashboard seguro del Home Server que muestra servicios accesibles y estado del sistema sin exponer información sensible.

## 🚀 Características

- **🌐 Servicios accesibles**: Lista solo servicios web públicos y protegidos
- **📊 Estado del sistema**: Información segura (sin hostname real, IPs, o rutas)
- **🔒 Separación por seguridad**: Servicios públicos vs protegidos claramente diferenciados
- **📈 Métricas útiles**: Uso de memoria, disco y carga del sistema en porcentajes
- **🐳 Estado de contenedores**: Solo conteos básicos sin nombres ni detalles
- **🌐 Dominio principal**: Accesible directamente desde el dominio sin subdominio
- **♻️ Auto-actualización**: Refresco automático cada 30 segundos
- **🛡️ Información filtrada**: No expone rutas internas, configuraciones o detalles del sistema

## 🛠️ Tecnologías

- **Node.js 18** con Express
- **YAML parser** para leer configuración de stacks
- **Docker CLI** para obtener información de contenedores
- **Comandos del sistema** para estadísticas del servidor

## 📡 API Endpoints

- `GET /` - Dashboard web principal
- `GET /api/system` - Estado del sistema (información segura)
- `GET /api/services` - Servicios web accesibles (públicos y protegidos)
- `GET /api/dashboard` - Datos completos del dashboard

### 🛡️ Información de Seguridad

**Datos que NO se exponen:**
- Hostname real del servidor
- Direcciones IP internas
- Rutas del sistema de archivos
- Nombres de contenedores específicos
- Configuraciones detalladas
- Logs o información sensible

**Datos seguros que SÍ se muestran:**
- Porcentajes de uso de recursos
- Estado general del sistema (low/medium/high)
- URLs de servicios públicos
- Conteo básico de contenedores
- Tiempo de actividad

## 🔧 Configuración

El servicio lee automáticamente:
- `/config/stacks.yml` - Configuración de stacks y servicios
- Variables de entorno desde `common.env`
- Información del sistema en tiempo real

## 📦 Despliegue

```bash
# Generar archivos .env
./scripts/generate-docker-envs.sh dashboard

# Desplegar el stack
./scripts/deploy.sh dashboard
```

## 🧪 Desarrollo Local

Para probar el dashboard localmente:

```bash
# Usar el script de desarrollo (recomendado)
./dev-server.sh

# O manualmente
npm install
npm start
```

### 📋 Gestión de Dependencias

El `package-lock.json` **está incluido en el repositorio** por las siguientes razones:

- **✅ Builds reproducibles**: Garantiza que todas las instalaciones usen las mismas versiones exactas
- **✅ Seguridad**: Previene instalación de versiones vulnerables 
- **✅ Velocidad CI/CD**: `npm ci` es más rápido que `npm install`
- **✅ Determinismo**: Elimina variabilidad entre entornos (dev/staging/prod)

**Flujo de trabajo:**
1. Al agregar dependencias: `npm install <package>` (actualiza package.json y package-lock.json)
2. Al instalar en desarrollo: `npm ci` (instala desde lock file)
3. En Docker: `npm ci --omit=dev` (instala solo dependencias de producción)

**Nota**: Esta es la práctica recomendada para aplicaciones (a diferencia de librerías).

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
