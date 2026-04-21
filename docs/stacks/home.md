# Stack: Home (Dashboard)

Dashboard central de HMS - página de inicio con enlaces a todos los servicios disponibles.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 1 servicio (Dashboard HMS) |
| **Puertos Expuestos** | Ninguno (accesible vía HTTPS) |
| **Almacenamiento** | < 1MB |

## 📝 Descripción

El stack **home** proporciona una página web que actúa como **punto de entrada central** a todos los servicios de HMS. Muestra estado del sistema, métricas en tiempo real y enlaces a todos los servicios desplegados, con botones para arrancar y parar cada stack directamente desde el navegador.

## 🔧 Servicios Incluidos

### 1. Dashboard HMS - Portal Centralizado
Página de inicio con estado de stacks y control de los mismos

- **URL**: `https://{DOMAIN}` (raíz del dominio)
- **Protegido**: ✅ Parcial — lectura pública, control autenticado (ver sección Seguridad)
- **Función**: Portal central, estado del sistema, métricas, control de stacks

## 📋 Configuración Requerida

> Este stack no requiere configuración específica en `config.toml`. Solo necesita la configuración global del sistema.

### 🔧 Variables del Sistema

```toml
[global]
domain = "ejemplo.com"              # Tu dominio principal
```

## 📁 Almacenamiento

El stack home es completamente **stateless** - no persiste ningún dato en disco. Todo se genera dinámicamente en tiempo de ejecución.

## 🎯 Características

- ✅ Descubrimiento automático de servicios
- ✅ Estado y métricas en tiempo real (CPU, RAM, red) por stack
- ✅ Botones ▶/■ para arrancar y parar stacks desde el navegador
- ✅ Integración con etiquetas `hms.description` de Docker
- ✅ Responsive design (funciona en mobile)

## 🔐 Seguridad

El dashboard usa **dos routers Traefik** sobre el mismo servicio:

| Ruta | Acceso | Descripción |
|------|--------|-------------|
| `https://{DOMAIN}/` | Público | Dashboard de solo lectura |
| `https://{DOMAIN}/api/stacks/*` | TinyAuth (Google OAuth) | Endpoints de control ▶/■ |

Al hacer click en un botón de control, si no hay sesión activa Traefik redirige al login de Google (`https://auth.{DOMAIN}`). Tras autenticarse, la acción se ejecuta y vuelve al dashboard automáticamente.

El stack **infra** está protegido y no puede detenerse desde el dashboard.
