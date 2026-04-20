# Stack: Helloworld (Stack de Ejemplo)

Stack minimalista de demostración con Nginx.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | 📚 Ejemplo |
| **Servicios** | 1 servicio (Nginx) |
| **Puertos Expuestos** | Ninguno (accesible vía HTTPS) |
| **Almacenamiento** | < 1MB |

## 📝 Descripción

Stack de demostración minimalista con un servidor Nginx que sirve una página HTML estática. Útil para testing de la infraestructura sin necesidad de configuración adicional.

## 🔧 Servicios Incluidos

### 1. Nginx - Servidor Web Estático
Servidor web para servir contenido HTML estático

- **URL**: `https://test.{DOMAIN}`
- **Protegido**: ❌ No (página pública)
- **Función**: Servir página estática de prueba, validar Traefik y DNS

## 📋 Configuración Requerida

> Este stack no requiere configuración específica en `config.toml`. Solo necesita la configuración global del sistema.

### 🔧 Variables del Sistema

```toml
[global]
domain = "ejemplo.com"              # Tu dominio principal
```

## 📁 Almacenamiento

El stack helloworld es prácticamente **stateless**. Solo contiene:

```
stacks/helloworld/html/             # Contenido estático
└── index.html                      # Página de prueba
```

## 🚀 Primeros Pasos

```bash
# 1. Validar configuración
hms validate helloworld

# 2. Levantar el stack
hms up helloworld

# 3. Esperar a que Traefik lo exponga (5-10 segundos)
sleep 5

# 4. Acceder
# https://test.ejemplo.com

# 5. Ver logs
hms logs helloworld -f
```
