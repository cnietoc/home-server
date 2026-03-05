# Stack: Terraria (Servidor de Juego)

Servidor multijugador para el juego Terraria con **tModLoader** permitiendo persistencia de mundos, soporte para mods y configuración avanzada sin ejecutar como root.

## 📋 Overview

| Propiedad | Valor |
|-----------|-------|
| **Estado** | ✅ Estable |
| **Servicios** | 1 servicio (Servidor Terraria con tModLoader) |
| **Puertos Expuestos** | 7777 (TCP - juego) |
| **Imagen** | `hexlo/terraria-tmodloader-server:latest` |
| **Almacenamiento** | ~500MB-2GB (mundos, configuración, mods, logs) |
| **Seguridad** | ✅ No ejecuta como root |

## 🎮 Descripción

Stack que proporciona un servidor multijugador para el juego **Terraria** con **tModLoader**, el loader de mods oficial para Terraria. tModLoader permite cargar mods personalizados, jugar con contenido extendido y crear experiencias de juego únicas.

Este stack utiliza la imagen `hexlo/terraria-tmodloader-server` que ejecuta el servidor **sin permisos de root**, mejorando la seguridad del sistema. Soporta configuración mediante variables de entorno y permite cargar mods fácilmente.

Los jugadores pueden conectarse al servidor para jugar en mundos persistentes compartidos con todos los mods instalados sincronizados automáticamente.

## 🔧 Servicios Incluidos

### 1. Servidor Terraria con tModLoader - Juego Multijugador
Servidor de juego con soporte para múltiples jugadores simultáneos y carga de mods

- **Dirección**: `servidor.local:7777` o `IP-SERVIDOR:7777`
- **Puerto**: 7777 (TCP)
- **Protegido**: ✅ Sí (contraseña opcional)
- **Función**: Servidor multijugador persistente, gestión de mundos, soporte de mods, coordinación de jugadores

## 📋 Configuración Requerida

> Este stack requiere configuración específica en `config.toml` para funcionar correctamente.

### 🔧 Configuración Obligatoria

```toml
[terraria]
world_name = "My Terraria World"           # Nombre del mundo
```

### 🔧 Configuración Opcional

```toml
[terraria]
password = ""                              # Contraseña del servidor (vacío = sin contraseña)
world_size = "2"                           # Tamaño: 1=pequeño, 2=medio, 3=grande
difficulty = "normal"                      # Dificultad: normal, expert, master, journey
motd = "Welcome to my Terraria server!"    # Mensaje al conectar
max_players = "8"                          # Máximo de jugadores simultáneos
language = "en-US"                         # Idioma del servidor (en-US, es-ES, etc)
```

## 🗂️ Estructura de Datos

```
data/
└── terraria/
    ├── worlds/              # Mundos persistentes de Terraria (.wld y .twld)
    ├── config/              # Configuración de tModLoader
    ├── plugins/             # Mods de tModLoader (.tmod)
    └── logs/                # Logs del servidor
```

## 🔐 Variables de Entorno Disponibles

El stack utiliza las siguientes variables de entorno desde `config.toml`:

- `STACK_PREFIX`: Nombre del contenedor
- `TZ`: Zona horaria
- `WORLD_NAME`: Nombre del mundo
- `WORLD_SIZE`: Tamaño del mundo (1=pequeño, 2=medio, 3=grande)
- `DIFFICULTY`: Dificultad del juego (normal, expert, master, journey)
- `MOTD`: Mensaje del día
- `LANGUAGE`: Idioma del servidor (en-US, es-ES, etc)
- `MAX_PLAYERS`: Máximo de jugadores
- `PASSWORD`: Contraseña del servidor (opcional)

## 📝 Notas de Configuración

### Tamaños de Mundo
- **1**: Pequeño (~50MB)
- **2**: Medio (~150MB) - Recomendado
- **3**: Grande (~250MB)

### Niveles de Dificultad
- **normal**: Normal
- **expert**: Experto
- **master**: Maestro
- **journey**: Viaje

### Puertos
El servidor utiliza el puerto **7777/TCP** para el tráfico del juego.

## 🔌 Conexión del Cliente

Los jugadores pueden conectarse al servidor utilizando:

1. Abrir Terraria
2. Seleccionar "Jugar" → "Servidor Multijugador"
3. Conectar a: `IP-DEL-SERVIDOR:7777`
4. Introducir la contraseña si es requerida

## 🔧 Mods de tModLoader

tModLoader permite extender la funcionalidad del juego mediante mods. Los mods son archivos `.tmod` que se cargan automáticamente al iniciar el servidor.

### Instalación de Mods

Hay dos formas de instalar mods en el servidor:

#### Método 1: Desde el Steam Workshop (Recomendado)
1. **Descarga los mods** en tu cliente de Terraria con tModLoader
2. **Copia los archivos `.tmod`** desde tu carpeta local:
   - Windows: `%USERPROFILE%\Documents\My Games\Terraria\tModLoader\Mods\`
   - Linux: `~/.local/share/Terraria/tModLoader/Mods/`
   - Mac: `~/Library/Application Support/Terraria/tModLoader/Mods/`
3. **Pega los archivos** en `data/terraria/plugins/`
4. **Reinicia el servidor** para que cargue los mods

#### Método 2: Descarga Manual
1. **Descarga el mod** (archivo `.tmod`) desde [tModLoader Mod Browser](https://steamcommunity.com/workshop/browse/?appid=1281930)
2. **Copia a** `data/terraria/plugins/`
3. **Reinicia el servidor** para que cargue el mod

### Estructura de la Carpeta de Mods

```
data/terraria/plugins/
├── CalamityMod.tmod
├── ThoriumMod.tmod
├── MagicStorage.tmod
└── RecipeBrowser.tmod
```

### Mods Recomendados

| Mod | Descripción | Función |
|-----|-------------|---------|
| **Calamity Mod** | Contenido masivo | Añade +2000 nuevos items, bosses y mecánicas |
| **Thorium Mod** | Expansión equilibrada | Nuevas clases, items y bosses |
| **Magic Storage** | Almacenamiento | Sistema de almacenamiento avanzado |
| **Recipe Browser** | Explorador de recetas | Busca crafting y items fácilmente |
| **Boss Checklist** | Lista de bosses | Rastrea progreso de bosses y eventos |

### Compatibilidad de Mods

⚠️ **Importante**: Todos los jugadores deben tener instalados **exactamente los mismos mods** que el servidor para poder conectarse.

### Verificar Mods Cargados

Los mods cargados se muestran en los logs del servidor en `data/terraria/logs/`.

### Solución de Problemas

- **El mod no se carga**: Asegúrate que el archivo `.tmod` está en `data/terraria/plugins/` y reinicia el servidor
- **El servidor no inicia**: Revisa los logs en `data/terraria/logs/` para ver errores de compatibilidad entre mods
- **No puedo conectarme**: Verifica que tienes instalados exactamente los mismos mods que el servidor
- **Conflicto entre mods**: Algunos mods son incompatibles entre sí, revisa la documentación de cada mod

Por defecto, los mundos y configuración del servidor se guardan en `data/terraria/`:
- Los mundos se encuentran en `worlds/`
- La configuración de tModLoader en `config/`
- Los mods instalados en `plugins/`

Se recomienda hacer backup regularmente de la carpeta `data/terraria/`.

## 📚 Enlaces Útiles

- [Documentación oficial de Terraria](https://www.terraria.org/)
- [tModLoader en Steam](https://store.steampowered.com/app/1281930/tModLoader/)
- [tModLoader GitHub Oficial](https://github.com/tModLoader/tModLoader)
- [tModLoader Wiki](https://github.com/tModLoader/tModLoader/wiki)
- [Steam Workshop - Mods de tModLoader](https://steamcommunity.com/workshop/browse/?appid=1281930)
- [Docker Image: hexlo/terraria-tmodloader-server](https://github.com/hexlo/terraria-tmodloader-server)



