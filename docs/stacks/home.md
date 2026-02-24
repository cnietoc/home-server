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

El stack **home** proporciona una página web que actúa como **punto de entrada central** a todos los servicios de HMS. Muestra enlaces organizados a los diferentes servicios desplegados (Jellyfin, Radarr, Sonarr, Traefik Dashboard, etc.) con descripciones y estado de cada uno.

## 🔧 Servicios Incluidos

### 1. Dashboard HMS - Portal Centralizado
Página de inicio con enlaces a todos los servicios

- **URL**: `https://{DOMAIN}` (raíz del dominio)
- **Protegido**: ❌ No (acceso público)
- **Función**: Portal central, descubrimiento de servicios, estado de sistema, enlaces rápidos

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
- ✅ Enlaces a todas las aplicaciones desplegadas
- ✅ Mostrar estado de cada servicio
- ✅ Integración con etiquetas `hms.description` de Docker
- ✅ Responsive design (funciona en mobile)
- ✅ Acceso rápido a aplicaciones

## 🔐 Seguridad

El dashboard home **no tiene protección** - es públicamente accesible. Está diseñado para ser el punto de entrada visible del sistema.
