# Stack: Infra (Infraestructura Base)

Stack fundamental que proporciona servicios centrales para el sistema.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 3 servicios (Traefik, TinyAuth, Watchtower) |
| **Puertos Expuestos** | 80 (HTTP), 443 (HTTPS), 8080 (Traefik Dashboard) |
| **Almacenamiento** | ~1GB (logs, certificados, config) |

## 🔧 Servicios Incluidos

### 1. Traefik - Proxy Reverso y SSL
Proxy reverso con generación automática de certificados SSL

- **URL**: `https://traefik.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Routing de peticiones, generación automática de certificados SSL con Let's Encrypt vía DNS Challenge (Cloudflare), balanceo de carga

### 2. TinyAuth - Autenticación Centralizada
Servicio de autenticación OAuth2 para proteger aplicaciones

- **URL**: `https://auth.{DOMAIN}`
- **Protegido**: ❌ No (servicio de autenticación)
- **Función**: Autenticación vía Google OAuth2, whitelist de usuarios, protección de servicios mediante forward auth

### 3. Watchtower - Actualizador Automático
Actualización automática de imágenes Docker

- **URL**: Sin acceso web (servicio interno)
- **Protegido**: N/A (solo monitoreo interno)
- **Función**: Actualización automática de contenedores, limpieza de imágenes antiguas, notificaciones de actualizaciones

## 📋 Configuración Requerida

> Este stack requiere configuración específica en `config.toml` para funcionar correctamente.

### 🔧 Configuración Obligatoria

```toml
[global]
domain = "ejemplo.com"              # Tu dominio

[infra.cloudflare]
email = "admin@ejemplo.com"         # Email de cuenta Cloudflare
dns_api_token = "tu-token-api"      # Token API de Cloudflare con permisos DNS

[infra.auth]
google_client_id = "tu-client-id"   # OAuth Client ID de Google
google_client_secret = "tu-secret"  # OAuth Client Secret de Google
oauth_whitelist = "user@gmail.com"  # Emails autorizados (separados por coma)
```

### 🔧 Configuración Opcional

```toml
# Configuración de Watchtower (valores por defecto)
[infra.watchtower]
schedule = '0 0 */12 * * *'         # Cada 12 horas
notifications = "shoutrrr"          # Tipo de notificaciones
notification_url = "gotify://..."   # URL de notificaciones
notifications_level = "info"        # Nivel de notificaciones
log_level = "info"                  # Nivel de logs
```

> **💡 Nota**: Para obtener las credenciales de Google OAuth2, visita [Google Cloud Console](https://console.cloud.google.com/apis/credentials) y crea un proyecto OAuth 2.0.

## 📁 Estructura de Datos

```
data/infra/
├── traefik/
│   ├── certs/
│   │   └── acme.json        # Certificados SSL Let's Encrypt
│   └── logs/
│       ├── traefik.log      # Log principal
│       └── access.log       # Log de accesos
├── tinyauth/
│   └── database.sqlite      # Base de datos usuarios/sesiones
└── watchtower/              # (logs internos del contenedor)
```

## 🎯 Workflow Típico

1. **Traefik recibe peticiones**:
   - Escucha en puertos 80 (HTTP) y 443 (HTTPS)
   - Redirige automáticamente HTTP → HTTPS

2. **Validación de certificados**:
   - Si el dominio no tiene certificado, Traefik lo solicita a Let's Encrypt
   - Usa DNS Challenge con Cloudflare para validar
   - Guarda el certificado en `/certs/acme.json`

3. **Protección con TinyAuth**:
   - Servicios marcados con middleware `tinyauth@docker` requieren autenticación
   - TinyAuth valida sesiones mediante forward auth
   - Usuarios deben estar en la whitelist OAuth

4. **Watchtower monitorea**:
   - Revisa imágenes cada 12 horas (configurable)
   - Descarga actualizaciones disponibles
   - Reinicia contenedores actualizados
   - Limpia imágenes antiguas

## 🔐 Certificados SSL

- **Generación**: Automática con Let's Encrypt vía DNS Challenge (Cloudflare)
- **Ubicación**: `/data/infra/traefik/certs/acme.json`
- **Renovación**: Automática (30 días antes de expirar)
- **Wildcard**: Soportado (`*.ejemplo.com`)

### Requisitos para SSL
1. Dominio configurado en Cloudflare
2. Token API con permisos `Zone:DNS:Edit`
3. DNS apuntando al servidor (registro A o CNAME)
