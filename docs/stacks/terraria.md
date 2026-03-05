# Stack: Terraria (Servidor de Juego)

Servidor multijugador para el juego Terraria con **tShock oficial** (modificación mantenida por Pryaxis) permitiendo persistencia de mundos y configuración avanzada.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 1 servicio (Servidor Terraria con tShock Oficial) |
| **Puertos Expuestos** | 7777 (TCP - juego) |
| **Imagen** | `ghcr.io/pryaxis/tshock:latest` (Oficial) |
| **Almacenamiento** | ~500MB-2GB (mundos, configuración, logs) |

## 🎮 Descripción

Stack que proporciona un servidor multijugador para el juego **Terraria** con **tShock**, la modificación oficial mantenida por **Pryaxis**. tShock añade comandos administrativos, plugins, protección de regiones y muchas más características avanzadas.

Los jugadores pueden conectarse al servidor para jugar en mundos persistentes compartidos con toda la funcionalidad extendida de tShock.

## 🔧 Servicios Incluidos

### 1. Servidor Terraria con tShock - Juego Multijugador
Servidor de juego con soporte para múltiples jugadores simultáneos y extensiones administrativas

- **Dirección**: `servidor.local:7777` o `IP-SERVIDOR:7777`
- **Puerto**: 7777 (TCP)
- **Protegido**: ✅ Sí (contraseña recomendada)
- **Función**: Servidor multijugador persistente, gestión de mundos, coordinación de jugadores, plugins de tShock

## 📋 Configuración Requerida

> Este stack requiere configuración específica en `config.toml` para funcionar correctamente.

### 🔧 Configuración Obligatoria

```toml
[terraria]
password = "tu-contraseña"                 # Contraseña del servidor
```

### 🔧 Configuración Opcional

```toml
[terraria]
world_name = "Terraria World"              # Nombre del mundo
world_size = "1"                           # Tamaño: 0=pequeño, 1=medio, 2=grande
difficulty = "0"                           # Dificultad: 0=normal, 1=experto, 2=maestro
motd = "Welcome to my Terraria server!"    # Mensaje al conectar
max_players = "255"                        # Máximo de jugadores simultáneos
secure = "1"                               # Activar modo seguro (1=sí, 0=no)
language = "en"                            # Idioma del servidor (en, de, fr, es, etc)
```

## 🗂️ Estructura de Datos

```
data/
└── terraria/
    ├── worlds/              # Mundos persistentes de Terraria
    ├── config/              # Configuración de tShock y plugins
    ├── plugins/             # Plugins de tShock (.dll)
    └── logs/                # Logs del servidor
```

## 🔐 Variables de Entorno Disponibles

El stack utiliza las siguientes variables de entorno desde `config.toml`:

- `STACK_PREFIX`: Nombre del contenedor
- `TZ`: Zona horaria
- `TSHOCK_WORLD`: Nombre del mundo (mapea a `WORLD_NAME`)
- `TSHOCK_WORLDSIZE`: Tamaño del mundo (mapea a `WORLD_SIZE`)
- `TSHOCK_DIFFICULTY`: Dificultad del juego (mapea a `DIFFICULTY`)
- `TSHOCK_MOTD`: Mensaje del día (mapea a `MOTD`)
- `TSHOCK_SECURE`: Modo seguro (mapea a `SECURE`)
- `TSHOCK_LANGUAGE`: Idioma del servidor (mapea a `LANGUAGE`)
- `TSHOCK_MAXPLAYERS`: Máximo de jugadores (mapea a `MAX_PLAYERS`)

## 📝 Notas de Configuración

### Tamaños de Mundo
- **0**: Pequeño (~50MB)
- **1**: Medio (~150MB) - Recomendado
- **2**: Grande (~250MB)

### Niveles de Dificultad
- **0**: Normal
- **1**: Experto
- **2**: Maestro
- **3**: Viaje

### Puertos
El servidor utiliza el puerto **7777/TCP** para el tráfico del juego.

## 🔌 Conexión del Cliente

Los jugadores pueden conectarse al servidor utilizando:

1. Abrir Terraria
2. Seleccionar "Jugar" → "Servidor Multijugador"
3. Conectar a: `IP-DEL-SERVIDOR:7777`
4. Introducir la contraseña si es requerida

## 🔧 Plugins de tShock

tShock permite extender la funcionalidad del servidor mediante plugins. Los plugins son archivos `.dll` que se cargan automáticamente al iniciar el servidor.

### Instalación de Plugins

1. **Descargar el plugin** (archivo `.dll`)
2. **Copiar a** `data/terraria/plugins/`
3. **Reiniciar el servidor** para que cargue el plugin

### Estructura de la Carpeta de Plugins

```
data/terraria/plugins/
├── Essentials.dll
├── ChatFilter.dll
├── AntiCheat.dll
└── OtherPlugin.dll
```

### Plugins Recomendados

| Plugin | Descripción | Función |
|--------|-------------|---------|
| **Essentials** | Comandos extendidos | Utilidades y comandos administrativos |
| **ChatFilter** | Filtrado de chat | Filtrar palabras y mensajes spam |
| **AntiCheat** | Detección de trucos | Prevenir hacks y exploits |
| **WorldEdit** | Editor de mundo | Herramientas de construcción avanzada |
| **Respawn** | Control de respawns | Personalizar mecánicas de respawn |

### Verificar Plugins Cargados

Para ver los plugins activos en tu servidor:

1. Conecta al servidor como administrador en-game
2. Ejecuta el comando:
```
/plugins
```

Esto listará todos los plugins que están cargados y activos.

### Solución de Problemas

- **El plugin no se carga**: Asegúrate que está en `data/terraria/plugins/` y reinicia el servidor
- **El servidor no inicia**: Revisa los logs en `data/terraria/logs/` para ver errores de compatibilidad
- **Comando no funciona**: Verifica que tienes los permisos necesarios con `/admin`

Por defecto, los mundos y configuración del servidor se guardan en `data/terraria/`:
- Los mundos se encuentran en `worlds/`
- La configuración de tShock en `config/`

Se recomienda hacer backup regularmente de la carpeta `data/terraria/`.

## 📚 Enlaces Útiles

- [Documentación oficial de Terraria](https://www.terraria.org/)
- [tShock GitHub Oficial](https://github.com/Pryaxis/TShock)
- [tShock Wiki](https://github.com/Pryaxis/TShock/wiki)
- [tShock Docker Documentation](https://github.com/Pryaxis/TShock/wiki/docker)
- [Docker Image: ghcr.io/pryaxis/tshock](https://ghcr.io/pryaxis/tshock)



