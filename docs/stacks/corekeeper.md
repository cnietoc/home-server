# Stack: Core Keeper (Servidor de Juego)

Servidor multijugador para el juego Core Keeper con persistencia de mundos y configuración basado en la imagen `escaping/core-keeper-dedicated`.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 1 servicio (Servidor Core Keeper) |
| **Almacenamiento** | ~2GB (guardados, configuración) |
| **Modo de Red** | SDR (Steam Datagram Relay) por defecto |

## 🎮 Descripción

Stack que proporciona un servidor multijugador para el juego **Core Keeper**. Los jugadores pueden conectarse al servidor para jugar en mundos persistentes compartidos. Utiliza la imagen `escaping/core-keeper-dedicated`.

## 🔧 Servicios Incluidos

### 1. Servidor Core Keeper - Juego Multijugador
Servidor de juego con soporte para múltiples jugadores simultáneos

- **Nombre del servidor**: Configurable con `WORLD_NAME`
- **Modo de red**: SDR (Steam Datagram Relay) - sin puertos que abrir en el firewall
- **Función**: Servidor multijugador persistente, gestión de mundos, coordinación de jugadores

## 📋 Configuración Requerida

> Este stack requiere configuración específica en `config.toml` para funcionar correctamente.

### 🔧 Configuración Obligatoria

```toml
[corekeeper]
password = "tu-contraseña"                 # Contraseña del servidor (vacío = sin contraseña)
```

### 🔧 Configuración Opcional

```toml
[corekeeper]
world_name = "Mi Mundo Core Keeper"        # Nombre del mundo/servidor (vacío = "Core Keeper Server")
game_id = ""                               # Game ID (vacío = generado automáticamente)
discord_webhook_url = ""                   # URL de webhook de Discord (opcional)
```

> **💡 Notas**:
> - El servidor usa **SDR (Steam Datagram Relay)** por defecto - no necesitas abrir puertos
> - El servidor descargará los archivos necesarios desde Steam la primera vez
> - Game ID se genera automáticamente y se guarda en `server-data/GameID.txt`
> - `ACTIVATE_ALL_CONTENT` está habilitado por defecto para activar todos los biomas

## 📁 Estructura de Datos

```
data/corekeeper/
├── server-files/        # Archivos del servidor Core Keeper
└── server-data/         # Guardados, configuración y GameID
    └── GameID.txt       # Identificador único del servidor
```

## 🚀 Uso

### Conectarse al Servidor (Modo SDR)

Por defecto, el servidor usa **Steam Datagram Relay (SDR)**, lo que significa que:
- ✅ No necesitas abrir puertos en el firewall
- ✅ La conexión se realiza a través de los servidores de Steam
- ✅ Mayor estabilidad en redes con NAT

1. **Abre Core Keeper** en tu computadora
2. **Ve a Multijugador** → **Unirse a servidor**
3. **Busca el servidor por nombre**: El servidor aparecerá en la lista de servidores públicos
4. **Conecta**: Selecciona el servidor y únete

### Obtener el Game ID

El servidor genera un Game ID único automáticamente. Para verlo:

```bash
# Revisa los logs
hms corekeeper logs
```

## 📚 Recursos Adicionales

- [Core Keeper - Sitio Oficial](https://www.corekeeperlegame.com/)
- [Core Keeper - Wiki](https://corekeeper.fandom.com/)
- [Core Keeper - Discord](https://discord.gg/corekeeper)
- [Imagen Docker - escaping/core-keeper-dedicated](https://github.com/escapingnetwork/core-keeper-dedicated)

## ⚠️ Notas Importantes

- El servidor requiere que los clientes tengan la misma versión del juego
- Los guardados se almacenan localmente y se persisten entre reinicios
- El primer inicio puede tardar varios minutos mientras descarga los archivos del servidor
