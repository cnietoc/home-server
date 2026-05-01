# Stack: Pets (Gatitos Aleatorios)

Web de gatitos aleatorios construida con Next.js 15.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 1 servicio (Next.js) |
| **Puertos Expuestos** | Ninguno (accesible vía HTTPS) |
| **Almacenamiento** | Stateless |

## 📝 Descripción

El stack **pets** sirve una web estática/dinámica construida con Next.js 15 en modo `standalone`. La imagen se construye localmente desde el código fuente incluido en `stacks/pets/` — no hay imagen externa en ningún registry.

## 🔧 Servicios Incluidos

### 1. Web - Gatitos Aleatorios

- **URL**: `https://pets.{DOMAIN}`
- **Protegido**: ❌ Acceso público
- **Función**: Muestra gatitos aleatorios

## 📋 Configuración Requerida

> Este stack no requiere configuración específica en `config.toml`. Solo necesita la configuración global del sistema.

```toml
[global]
domain = "ejemplo.com"   # Se usa para generar la URL pets.ejemplo.com
```

## 📁 Almacenamiento

El stack es completamente **stateless** — no monta ningún volumen ni escribe datos persistentes en disco.

## 🔐 Seguridad

| Ruta | Acceso | Descripción |
|------|--------|-------------|
| `https://pets.{DOMAIN}` | Público | Web accesible sin login |

## 🛠️ Build

La imagen se construye con el Dockerfile multi-stage incluido en `stacks/pets/`:

1. **deps** — instala dependencias (`npm ci`)
2. **builder** — ejecuta `next build` (output standalone)
3. **runner** — imagen mínima `node:22-alpine` con el servidor standalone

Para reconstruir manualmente:

```bash
hms pets down
hms pets up   # hace docker compose up --build
```

> Como la imagen es local, Watchtower está desactivado para este stack (`com.centurylinklabs.watchtower.enable: "false"`).
