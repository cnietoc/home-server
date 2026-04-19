# Stack: V Rising (Servidor de Juego)

Servidor multijugador para el juego V Rising con persistencia de mundo y configuración avanzada basado en la imagen `trueosiris/vrising`.

## 📋 Overview

| Propiedad             | Valor                                        |
|-----------------------|----------------------------------------------|
| **Estado**            | ✅ Estable                                    |
| **Servicios**         | 1 servicio (Servidor V Rising)               |
| **Puertos Expuestos** | 9876/UDP (juego), 9877/UDP (query)           |
| **Imagen**            | `trueosiris/vrising`                         |
| **Almacenamiento**    | ~5-10GB (binarios del servidor + guardados)  |
| **Tiempo de inicio**  | ⚠️ Hasta 10 minutos en el primer arranque    |

## 🎮 Descripción

Stack que proporciona un servidor multijugador para el juego **V Rising**. Los jugadores se convierten en vampiros recién despertados y deben sobrevivir, construir castillos y enfrentarse a poderosos jefes V Blood para absorber sus poderes.

El servidor soporta modos **PvE** y **PvP**, configuración granular de dificultad, multiplicadores de progresión y ciclo día/noche personalizable. La configuración se inyecta mediante variables de entorno con los prefijos `HOST_SETTINGS_` y `GAME_SETTINGS_`.

## 🔧 Servicios Incluidos

### 1. Servidor V Rising - Juego Multijugador

- **Puerto**: 9876/UDP (juego), 9877/UDP (query Steam)
- **Conexión**: Directa por IP o lista pública de Steam
- **Función**: Servidor multijugador persistente con mundo compartido

## 📋 Configuración Requerida

> Este stack requiere configuración específica en `config.toml` para funcionar correctamente.

### 🔧 Configuración en config.toml

```toml
[vrising]
server_name = "Home Server V Rising"   # Nombre visible en la lista de servidores
world_name  = "world1"                 # Nombre del directorio de guardado
gameport    = "9876"                   # Puerto UDP del juego
queryport   = "9877"                   # Puerto UDP de query (Steam browser)
password    = "mi-contraseña-segura"   # Contraseña de acceso (vacío = sin contraseña)
```

### ⚙️ Configuración avanzada (GameSettings y HostSettings)

El resto de opciones (modo PvE/PvP, dificultad, crafteo, ciclo día/noche, autosaves, RCON…) se configuran directamente editando los ficheros JSON que el servidor genera en el primer arranque:

```
data/vrising/persistentdata/Settings/
├── ServerHostSettings.json    # Configuración del servidor (visibilidad, puertos, autosave...)
└── ServerGameSettings.json    # Configuración del juego (dificultad, multiplicadores...)
```

Estos ficheros se generan con los valores por defecto la primera vez. Edítalos con el servidor parado y reinicia para aplicar los cambios.

## 📁 Estructura de Datos

```
data/vrising/
├── server/             # Binarios del servidor (excluidos de backup, ~5GB)
└── persistentdata/
    ├── Saves/          # Guardados del mundo
    └── Settings/       # ServerHostSettings.json, ServerGameSettings.json
```

> Los ficheros JSON en `Settings/` se generan al primer arranque y pueden editarse manualmente. Las variables de entorno tienen **prioridad** sobre estos ficheros.

## 🔌 Conexión al Servidor

### Servidor privado (configuración por defecto)

El servidor **no aparece en listas públicas**. Los jugadores deben conectarse directamente:

1. Abrir V Rising
2. **Play → Find Servers → Direct Connect**
3. Introducir `IP-DEL-SERVIDOR:9876`
4. Introducir la contraseña si hay una configurada

⚠️ Los puertos **9876 y 9877 UDP** deben estar abiertos y redirigidos en el router para acceso desde internet.

### Servidor público (lista de Steam)

```toml
[vrising]
list_on_steam = "true"
list_on_eos   = "true"
hide_ip       = "false"
```

Los jugadores lo encuentran en: **Play → Find Servers → Official/Community** buscando por `server_name`.

## 💾 Persistencia de Datos

Los binarios del servidor (`/server`) se excluyen de los backups automáticamente porque se descargan solos al arrancar. Solo se respalda `/persistentdata` (guardados y settings).

```toml
[vrising.backups]
exclude = ["/server/"]
```

## 📚 Recursos Adicionales

- [V Rising - Sitio Oficial](https://www.playvrising.com/)
- [V Rising - Wiki](https://vrising.fandom.com/wiki/V_Rising_Wiki)
- [Stunlock Studios - Guía servidor dedicado](https://github.com/StunlockStudios/vrising-dedicated-server-instructions)
- [Imagen Docker - trueosiris/vrising](https://github.com/TrueOsiris/docker-vrising)

## ⚠️ Notas Importantes

- El primer arranque descarga los binarios del servidor y puede tardar **hasta 10 minutos**
- Los clientes deben tener la **misma versión del juego** que el servidor
- Con `rcon_enabled = "true"` se expone el puerto 25575 TCP — añadirlo a los `ports` del compose si se necesita acceso externo
- Los cambios en `HOST_SETTINGS_` y `GAME_SETTINGS_` requieren reiniciar el contenedor para aplicarse
