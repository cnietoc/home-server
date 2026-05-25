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
server_name          = "Home Server V Rising"   # Nombre visible en la lista de servidores
world_name           = "world1"                 # Nombre del directorio de guardado
gameport             = "9876"                   # Puerto UDP del juego
queryport            = "9877"                   # Puerto UDP de query (Steam browser)
password             = "mi-contraseña-segura"   # Contraseña de acceso (vacío = sin contraseña)
game_settings_preset = "StandardPvE"            # Preset de dificultad base
```

### ⚙️ Preset y ajustes QoL

El servidor arranca con un preset de dificultad base y encima se aplican overrides individuales de calidad de vida:

```toml
[vrising]
game_settings_preset = "StandardPvE"  # Preset base (StandardPvE, HardcorePvE, StandardPvP…)

# QoL overrides — castillo y progresión
teleport_bound_items = "0"      # 0 = puedes teleportarte con recursos
castle_decay_rate    = "0.1"    # decay de castillos muy reducido
blood_essence_drain  = "0.5"    # drenaje de esencia del corazón reducido a la mitad
material_yield       = "1.5"    # +50% materiales al picar/talar nodos
craft_rate           = "2.0"    # crafteo 2x más rápido
refinement_rate      = "2.0"    # refinado 2x más rápido
day_duration         = "720"    # duración del ciclo día/noche en segundos (defecto: 1080)

# QoL overrides — drops y farmeo
drop_table_general        = "1.5"  # +50% drops generales de enemigos
drop_table_missions       = "1.5"  # +50% botín de misiones de sirvientes
drop_table_stygian_shards = "1.5"  # +50% Stygian Shards en Rift Incursions
inventory_stacks          = "2.0"  # pilas 2x más grandes
blood_essence_yield       = "1.5"  # +50% esencia al matar/exprimir corazones
```

> **Presets disponibles**: `StandardPvE`, `HardcorePvE`, `StandardPvP`, `HardcorePvP`, `SoloPvP`. Consulta el PDF de referencia en `stacks/vrising/` para el listado completo de valores por preset.

Los overrides de `config.toml` tienen **prioridad** sobre el preset. Para cualquier otro ajuste fino, edita directamente los ficheros JSON generados en el primer arranque:

```
data/vrising/persistentdata/Settings/
├── ServerHostSettings.json    # Configuración del servidor (visibilidad, puertos, autosave...)
└── ServerGameSettings.json    # Configuración del juego (dificultad, multiplicadores...)
```

Estos ficheros se generan con los valores del preset la primera vez. Edítalos con el servidor parado y reinicia para aplicar los cambios.

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

HMS abre los puertos **`${GAMEPORT}` y `${QUERYPORT}` UDP** automáticamente en el router vía UPnP al hacer `hms vrising up` (ver [port-forwarding automático](../router-port-forwarding.md)).

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
