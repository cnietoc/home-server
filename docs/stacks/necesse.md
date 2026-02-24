# Stack: Necesse (Servidor de Juego)

Servidor multijugador para el juego Necesse con persistencia de mundos y configuración.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 1 servicio (Servidor Necesse) |
| **Puertos Expuestos** | 14159 (UDP - juego) |
| **Almacenamiento** | ~2GB (guardados, configuración, logs) |

## 🎮 Descripción

Stack que proporciona un servidor multijugador para el juego **Necesse**. Los jugadores pueden conectarse al servidor para jugar en mundos persistentes compartidos.

## 🔧 Servicios Incluidos

### 1. Servidor Necesse - Juego Multijugador
Servidor de juego con soporte para múltiples jugadores simultáneos

- **Dirección**: `servidor.local:14159` o `IP-SERVIDOR:14159`
- **Puerto**: 14159 (UDP)
- **Protegido**: ✅ Sí (contraseña opcional)
- **Función**: Servidor multijugador persistente, gestión de mundos, coordinación de jugadores

## 📋 Configuración Requerida

> Este stack requiere configuración específica en `config.toml` para funcionar correctamente.

### 🔧 Configuración Obligatoria

```toml
[necesse]
password = "tu-contraseña"                 # Contraseña del servidor
```

### 🔧 Configuración Opcional

```toml
[necesse]
motd = "Welcome to my Necesse server!"     # Mensaje al conectar (por defecto: vacío)
```

> **💡 Nota**: La contraseña puede ser vacía (`password = ""`) para permitir acceso público sin contraseña.

## 📁 Estructura de Datos

```
data/necesse/
├── saves/               # Mundos guardados
├── cfg/                 # Configuración del servidor
└── logs/                # Logs del servidor
```
## 🎯 Workflow Típico

1. **Servidor inicia**:
   - Lee configuración (MOTD, contraseña, slots)
   - Carga mundos existentes de `data/necesse/saves/`
   - Abre puerto UDP 14159
   - Está listo para recibir conexiones

2. **Jugadores se conectan**:
   - Inician Necesse en cliente
   - Ingresan IP-SERVIDOR:14159
   - Introducen contraseña si está configurada
   - Se sincronizan con el mundo del servidor

3. **Gameplay**:
   - Múltiples jugadores en el mismo mundo
   - Las acciones se sincronizan en tiempo real
   - El progreso se guarda automáticamente

4. **Mundos se guardan**:
   - Automáticamente durante el juego
   - Al cerrar el servidor
   - Archivos en `data/necesse/saves/`

## 🔐 Seguridad

### Contraseña del Servidor
- Protege contra acceso no autorizado
- Se recomienda usar contraseña fuerte si está expuesto a internet
- Si es red privada, puede ser vacía

### Acceso de Red
- El puerto 14159 (UDP) debe estar accesible para jugadores
- Si está detrás de NAT, configurar port-forwarding
- Firewall debe permitir UDP 14159

## 📊 Rendimiento

### Requisitos Mínimos
- **RAM**: 512MB por servidor
- **CPU**: 1 core (puede soportar más jugadores con más cores)
- **Almacenamiento**: ~2GB para guardados + logs

### Límites Recomendados
- **Máximo jugadores**: 25 (valor por defecto)
- **Tamaño mundial**: Limitado por almacenamiento disponible
