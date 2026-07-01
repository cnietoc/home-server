# Stack: Infra (Infraestructura Base)

Stack fundamental que proporciona servicios centrales para el sistema.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 4 servicios (Traefik, TinyAuth, Beszel hub + agente) |
| **Puertos Expuestos** | 80 (HTTP), 443 (HTTPS) |
| **Almacenamiento** | ~1GB (logs, certificados, config) |

## 🔧 Servicios Incluidos

### 1. Traefik - Proxy Reverso y SSL
Proxy reverso con generación automática de certificados SSL

- **URL**: `https://traefik.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth)
- **Función**: Routing de peticiones, generación automática de certificados SSL con Let's Encrypt vía DNS Challenge (Cloudflare), balanceo de carga

### 3. Beszel - Monitorización del Servidor
Monitor ligero de recursos del host y de todos los contenedores Docker

- **URL**: `https://monitor.{DOMAIN}`
- **Protegido**: ✅ Sí (tinyauth + login propio de Beszel)
- **Función**: Métricas históricas de CPU, memoria, red y disco por contenedor y del host; alertas configurables. Consta de dos servicios: el **hub** (interfaz web, puerto 8090 interno) y el **agente** (lee el socket de Docker en solo lectura y se comunica con el hub por un socket Unix compartido).
- **Primer arranque**: requiere copiar KEY y TOKEN del hub a `[infra.beszel]` en `config.toml` — ver el flujo en [docs/installation.md](../installation.md).
- **S.M.A.R.T.**: el agente usa la imagen `alpine` (incluye `smartctl`), monta `/dev` completo y añade las capabilities `SYS_RAWIO`/`SYS_ADMIN` para leer la salud de los discos. Esto no añade privilegio real más allá del que ya otorga el socket de Docker montado (equivalente a acceso root sobre el host).

### 2. TinyAuth - Autenticación Centralizada
Servicio de autenticación OAuth2 para proteger aplicaciones

- **URL**: `https://auth.{DOMAIN}`
- **Protegido**: ❌ No (servicio de autenticación)
- **Función**: Autenticación vía Google OAuth2, whitelist de usuarios, protección de servicios mediante forward auth

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
└── tinyauth/
    └── database.sqlite      # Base de datos usuarios/sesiones
└── beszel/
    ├── data/                # Base de datos del hub (métricas, usuarios)
    ├── agent/               # Fingerprint del agente
    └── socket/              # Socket Unix hub↔agente (excluido de backups)
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

4. **HMS daemon gestiona las actualizaciones**:
   - `hms update infra` descarga nuevas imágenes y recrea los containers
   - El job `update-infra` lo ejecuta automáticamente al arrancar y cada 24h
   - Puede causar un breve corte en el proxy durante la recreación

## 🔐 Certificados SSL

- **Generación**: Automática con Let's Encrypt vía DNS Challenge (Cloudflare)
- **Ubicación**: `/data/infra/traefik/certs/acme.json`
- **Renovación**: Automática (30 días antes de expirar)
- **Wildcard**: Soportado (`*.ejemplo.com`)

### Requisitos para SSL
1. Dominio configurado en Cloudflare
2. Token API con permisos `Zone:DNS:Edit`
3. DNS apuntando al servidor (registro A o CNAME)
