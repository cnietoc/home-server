# Port-forwarding automático en el router

HMS puede abrir y mantener automáticamente los puertos del router usando **UPnP IGD** (por defecto) o **NAT-PMP**, sin intervención manual.

## Cómo funciona

Los puertos se gestionan en tres momentos:

| Momento | Qué hace |
|---|---|
| `hms <stack> up` | Abre los puertos del stack inmediatamente tras arrancar |
| `hms <stack> down` | Cierra los puertos del stack |
| Job periódico (cada 30 min) | Refresca leases y restaura mapeos si el router se reinició |

## Qué stacks tienen puertos declarados

| Stack | Puerto(s) | Protocolo |
|---|---|---|
| infra (Traefik) | 80, 443 | TCP |
| terraria | 7777 | TCP |
| necesse | 14159 | UDP |
| vrising | 9876, 9877 (configurable) | UDP |
| media (qBittorrent) | 6881 | TCP + UDP |

## Activar en el router (ASUS RT-AC2900)

1. Accede a la admin del router: `http://192.168.1.1`
2. Ve a **WAN → Configuración de internet**
3. Habilita **"Enable UPnP"**
4. Guarda los cambios

Los mapeos activos se pueden ver en **WAN → NAT Passthrough → Show Active UPnP**.

## Configuración en HMS

`config.default.toml` ya incluye los defaults correctos. Normalmente no necesitas tocar nada.

Para personalizar, añade en tu `config.toml`:

```toml
[global]
host_ip = "192.168.X.X"   # IP del host en la LAN (se autoconfigura en `hms install`)

[router]
enabled        = true
backend        = "upnp"          # "upnp" | "natpmp" | "none"
gateway_ip     = ""              # opcional: IP del router (vacío = autodetección)
lease_duration = "3600"          # segundos (0 = permanente si el router lo soporta)
exclude_stacks = []              # p.ej. ["infra"] para gestionar Traefik a mano
```

## Docker y UPnP

UPnP usa **SSDP multicast** para descubrir el router, lo que requiere acceso a la red local del host. El daemon de HMS corre en bridge networking (red Docker privada) para no exponer su API en la LAN — desde ahí el multicast no alcanza al router.

**Solución automática**: cada vez que HMS necesita hacer una operación UPnP, lanza un contenedor efímero con `network_mode: host`, ejecuta la operación, y termina. El daemon principal permanece aislado.

No necesitas configurar nada para que esto funcione.

## Añadir puertos a un stack nuevo

En el `docker-compose.yml` del stack, añade el bloque `public_ports` dentro de `x-hms`:

```yaml
x-hms:
  description: "Mi servidor de juego"
  public_ports:
    - { port: 25565, protocol: tcp, description: "Minecraft server" }
    - { port: 19132, protocol: udp, description: "Bedrock" }
```

Las variables de config se sustituyen automáticamente (útil cuando el puerto es configurable):

```yaml
x-hms:
  public_ports:
    - { port: "${GAMEPORT}", protocol: udp, description: "Game server" }
```

## Comandos CLI

```bash
# Ver estado actual del router
hms system refresh-port-forwards --list

# Ver qué cambios se harían sin aplicarlos
hms system refresh-port-forwards --dry-run

# Reconciliar manualmente
hms system refresh-port-forwards

# Eliminar también mapeos que ya no están declarados
hms system refresh-port-forwards --prune
```

## Desactivar

Si no tienes UPnP disponible o prefieres gestión manual:

```toml
[router]
enabled = false
```

El job seguirá ejecutándose pero saldrá inmediatamente sin tocar el router.

## Consideraciones de seguridad

UPnP permite a cualquier proceso en la LAN abrir puertos en el router sin autenticación. HMS **solo abre los puertos que tú declaras** en `x-hms.public_ports`, pero si tienes otros servicios en la red local que usan UPnP, pueden abrir los suyos también.

Si esto es una preocupación, usa `backend = "natpmp"` (requiere configuración explícita) o `enabled = false` y gestiona los puertos a mano en la admin del router.
