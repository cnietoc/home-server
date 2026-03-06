# Stack: Terraria (Servidor de Juego)

Servidor multijugador para el juego Terraria con **tModLoader** permitiendo persistencia de mundos, soporte para mods y
configuración avanzada sin ejecutar como root.

## 📋 Overview

| Propiedad             | Valor                                            |
|-----------------------|--------------------------------------------------|
| **Estado**            | ✅ Estable                                        |
| **Servicios**         | 1 servicio (Servidor Terraria con tModLoader)    |
| **Puertos Expuestos** | 7777 (TCP - juego)                               |
| **Imagen**            | `passivelemon/terraria-docker:tmodloader-latest` |
| **Almacenamiento**    | ~500MB-2GB (mundos, configuración, mods, logs)   |
| **Seguridad**         | ✅ No ejecuta como root                           |

## 🎮 Descripción

Stack que proporciona un servidor multijugador para el juego **Terraria** con **tModLoader**, el loader de mods oficial
para Terraria. tModLoader permite cargar mods personalizados, jugar con contenido extendido y crear experiencias de
juego únicas.

Este stack utiliza la imagen `passivelemon/terraria-docker` que ejecuta el servidor **sin permisos de root**,
mejorando la seguridad del sistema. Soporta configuración mediante variables de entorno y permite cargar mods
fácilmente.

Los jugadores pueden conectarse al servidor para jugar en mundos persistentes compartidos con todos los mods instalados
sincronizados automáticamente.

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
password = "mi-contraseña-segura"                 # Contraseña del servidor (vacío = sin contraseña)
```

### 🔧 Configuración Opcional

```toml
[terraria]
world_name = "World"                       # Nombre del mundo (sin extensión)
world_size = "2"                           # Tamaño: 1=pequeño, 2=medio, 3=grande
difficulty = "0"                           # Dificultad: 0=normal, 1=expert, 2=master, 3=journey
motd = "Welcome to my Terraria server!"    # Mensaje al conectar
max_players = "16"                         # Máximo de jugadores simultáneos
secure = "1"                               # Protección anti-cheats (1=activado, 0=desactivado)
npcstream = "15"                           # Ayuda con saltos de entidades (0-60) - 15 recomendado
language = "en-US"                         # Idioma del servidor (ej: en-US, es-ES, fr-FR)
modpack = ""                               # Nombre del modpack en ModPacks/ (vacío = sin modpack)
```

## 📝 Notas de Configuración

### Tamaños de Mundo

- **1**: Pequeño (~50MB)
- **2**: Medio (~150MB) - Recomendado
- **3**: Grande (~250MB)

### Niveles de Dificultad

- **0**: Normal
- **1**: Experto
- **2**: Maestro
- **3**: Viaje (Journey Mode)

### Puertos

El servidor utiliza el puerto **7777/TCP** para el tráfico del juego.

## 🔌 Conexión del Cliente

Los jugadores pueden conectarse al servidor utilizando:

1. Abrir Terraria
2. Seleccionar "Jugar" → "Servidor Multijugador"
3. Conectar a: `IP-DEL-SERVIDOR:7777`
4. Introducir la contraseña si es requerida

## 🔧 Mods de tModLoader

tModLoader permite extender la funcionalidad del juego mediante mods. Esta imagen de Docker soporta la instalación de
mods mediante modpacks.

### Instalación de Mods

⚠️ **Importante**: No incluyas mods que solo funcionan del lado del cliente (client-side only) en el servidor. Estos
mods solo afectan al cliente como texturas, shaders, RPC, etc.

#### Método: Modpacks (Recomendado)

1. **En tModLoader de tu cliente**, habilita los mods que quieres usar
2. **Ve a la sección de mod packs**
3. **"Save Enabled as New Mod Pack"** (Guardar habilitados como nuevo Mod Pack)
4. **"Open Mod Pack folder"** (Abrir carpeta de Mod Pack)
5. **Copia la carpeta del modpack** que quieres usar en el servidor
6. **Pégala en** `data/terraria/ModPacks/`
7. **Configura la variable** `modpack` en `config.toml` con el nombre del modpack
8. **Reinicia el servidor**

Asegúrate de que el modpack tenga un archivo `enabled.json` con los mods que quieres, de lo contrario el servidor no
iniciará.

### Estructura de la Carpeta de Mods

```
data/terraria/
├── ModPacks/
│   └── MiModpack/
│       ├── enabled.json
│       └── Mods/
│           ├── CalamityMod.tmod
│           ├── ThoriumMod.tmod
│           └── MagicStorage.tmod
└── Worlds/
```

### Mods Recomendados

| Mod                | Descripción           | Función                                      |
|--------------------|-----------------------|----------------------------------------------|
| **Calamity Mod**   | Contenido masivo      | Añade +2000 nuevos items, bosses y mecánicas |
| **Thorium Mod**    | Expansión equilibrada | Nuevas clases, items y bosses                |
| **Magic Storage**  | Almacenamiento        | Sistema de almacenamiento avanzado           |
| **Recipe Browser** | Explorador de recetas | Busca crafting y items fácilmente            |
| **Boss Checklist** | Lista de bosses       | Rastrea progreso de bosses y eventos         |

### Compatibilidad de Mods

⚠️ **Importante**: Todos los jugadores deben tener instalados **exactamente los mismos mods** que el servidor para poder
conectarse.

### Verificar Mods Cargados

Los mods cargados se muestran en los logs del servidor. Puedes verlos con:

```bash
hms terraria logs
```

### Solución de Problemas

- **El servidor no inicia**: Verifica que el modpack tenga un archivo `enabled.json` válido
- **El mod no se carga**: Revisa los logs del contenedor para ver errores de compatibilidad
- **No puedo conectarme**: Verifica que tienes instalados exactamente los mismos mods que el servidor
- **Conflicto entre mods**: Algunos mods son incompatibles entre sí, revisa la documentación de cada mod

## 💾 Persistencia de Datos

Por defecto, todos los datos del servidor se guardan en `data/terraria/`:

- Los mundos se encuentran en `Worlds/`
- Los modpacks en `ModPacks/`
- Los mods descargados en `Mods/`
- La configuración en `ModConfigs/`

## 📚 Enlaces Útiles

- [Documentación oficial de Terraria](https://www.terraria.org/)
- [tModLoader en Steam](https://store.steampowered.com/app/1281930/tModLoader/)
- [tModLoader GitHub Oficial](https://github.com/tModLoader/tModLoader)
- [tModLoader Wiki](https://github.com/tModLoader/tModLoader/wiki)
- [Steam Workshop - Mods de tModLoader](https://steamcommunity.com/workshop/browse/?appid=1281930)
- [Docker Image: passivelemon/terraria-docker](https://github.com/PassiveLemon/terraria-docker)
- [Releases de Terraria](https://github.com/PassiveLemon/terraria-docker/releases/)




