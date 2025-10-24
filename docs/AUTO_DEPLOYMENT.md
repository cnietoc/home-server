# Configuración de Deployment Automático

Este documento explica cómo configurar el deployment automático desde GitHub usando SSH.

## 📋 Requisitos

- Servidor con acceso SSH configurado
- Repositorio de GitHub con el código del home server
- Docker instalado en el servidor
- Configuración de entorno ya enlazada (`config/private/`)

## 🔧 Configuración en el Servidor

### 1. Generar clave SSH para GitHub Actions

```bash
# En tu servidor, generar una nueva clave SSH específica para GitHub Actions
ssh-keygen -t rsa -b 4096 -C "github-actions@home-server" -f ~/.ssh/github-actions

# Esto creará dos archivos:
# ~/.ssh/github-actions (clave privada)
# ~/.ssh/github-actions.pub (clave pública)
```

### 2. Configurar clave pública en el servidor

```bash
# Añadir la clave pública a authorized_keys
cat ~/.ssh/github-actions.pub >> ~/.ssh/authorized_keys

# Verificar permisos
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

### 3. Configurar usuario para deployment

Opción A: Usar tu usuario actual (más simple):
```bash
# Ya tienes todo configurado, solo asegúrate de que el proyecto esté en la ubicación correcta
pwd  # Anotar la ruta completa del proyecto
```

Opción B: Crear usuario dedicado (más seguro):
```bash
# Crear usuario específico para deployments
sudo useradd -m -s /bin/bash github-deploy
sudo usermod -aG docker github-deploy

# Configurar SSH para el nuevo usuario
sudo mkdir -p /home/github-deploy/.ssh
sudo cp ~/.ssh/github-actions.pub /home/github-deploy/.ssh/authorized_keys
sudo chown -R github-deploy:github-deploy /home/github-deploy/.ssh
sudo chmod 700 /home/github-deploy/.ssh
sudo chmod 600 /home/github-deploy/.ssh/authorized_keys

# Clonar el repositorio en la home del usuario
sudo -u github-deploy git clone <tu-repo-url> /home/github-deploy/home-server
sudo -u github-deploy ln -sf /ruta/a/tu/configuracion /home/github-deploy/home-server/config/private
```

### 4. Probar conexión SSH

```bash
# Desde tu máquina local, probar la conexión
ssh -i ~/.ssh/github-actions usuario@tu-servidor "echo 'Conexión SSH exitosa'"
```

## 🐙 Configuración en GitHub

### 1. Añadir Secrets al repositorio

Ve a tu repositorio en GitHub → Settings → Secrets and variables → Actions

Añade estas variables de entorno:

| Secret Name | Descripción | Valor |
|-------------|-------------|-------|
| `SSH_PRIVATE_KEY` | Clave privada SSH | Contenido completo de `~/.ssh/github-actions` |
| `SSH_HOST` | IP o dominio del servidor | `tu-servidor.com` o `192.168.1.100` |
| `SSH_USER` | Usuario SSH | `tu-usuario` o `github-deploy` |
| `PROJECT_PATH` | Ruta del proyecto en el servidor | `/home/usuario/home-server` |

### 2. Copiar la clave privada

```bash
# En tu servidor, mostrar la clave privada para copiarla
cat ~/.ssh/github-actions

# Copiar TODO el contenido (incluyendo -----BEGIN y -----END)
# y pegarlo en la variable SSH_PRIVATE_KEY de GitHub
```

### 3. Configurar valores específicos

**SSH_HOST**: La IP o dominio de tu servidor
- Si tienes dominio: `mi-servidor.com`
- Si usas IP: `192.168.1.100`
- Si usas puerto SSH personalizado: añádelo en el workflow

**SSH_USER**: El usuario que usarás
- Usuario actual: tu nombre de usuario
- Usuario dedicado: `github-deploy`

**PROJECT_PATH**: Ruta completa donde está el proyecto
- Ejemplo: `/home/usuario/home-server`
- Ejemplo con usuario dedicado: `/home/github-deploy/home-server`

## 🚀 Cómo funciona

### Triggers automáticos

El deployment se ejecuta automáticamente cuando:
- Haces `git push` a la rama `main` o `master`
- Ejecutas manualmente desde GitHub Actions

### Deployment manual

Puedes ejecutar deployment manual con opciones:
1. Ve a tu repositorio en GitHub
2. Actions → Deploy Home Server
3. Click "Run workflow"
4. Selecciona opciones:
   - **Force deploy**: Redesplegar todo sin detección de cambios
   - **Recreate containers**: Recrear contenedores completamente

### Lo que hace el workflow

1. **Checkout**: Descarga el código del repositorio
2. **SSH Setup**: Configura la conexión SSH segura
3. **Connection Test**: Verifica que puede conectarse al servidor
4. **Deploy**: Se conecta al servidor y ejecuta:
   - `git pull` para obtener últimos cambios
   - `chmod +x scripts/*.sh` para hacer scripts ejecutables
   - `./scripts/auto-deploy.sh` que llama al `deploy.sh` con logging mejorado

## 📊 Monitoring y Logs

### Ver logs en GitHub

- Ve a Actions → última ejecución
- Podrás ver todo el output del deployment

### Ver logs en el servidor

```bash
# Ver log del último deployment
tail -50 ~/home-server/deployment.log

# Ver logs en tiempo real durante deployment
tail -f ~/home-server/deployment.log
```

### Estados del deployment

- ✅ **Success**: Todo desplegado correctamente
- ❌ **Failure**: Error durante el deployment
- 🟡 **In Progress**: Deployment ejecutándose

## 🔒 Seguridad

### Buenas prácticas implementadas

- ✅ Clave SSH específica para GitHub Actions
- ✅ Usuario dedicado opcional para deployments
- ✅ Conexión SSH verificada antes del deployment
- ✅ Scripts ejecutables solo cuando sea necesario
- ✅ Logs detallados para auditoría

### Recomendaciones adicionales

1. **Firewall**: Asegúrate de que solo GitHub Actions pueda acceder al SSH
2. **Backup**: Haz backup antes de deployments importantes
3. **Testing**: Prueba cambios en rama separada antes de main
4. **Monitoring**: Configura alertas si el deployment falla

## 🛠️ Troubleshooting

### Error: "Permission denied (publickey)"
- Verifica que la clave privada esté correcta en GitHub Secrets
- Comprueba que la clave pública esté en `authorized_keys`
- Verifica permisos de archivos SSH

### Error: "Host key verification failed"
- El workflow incluye `ssh-keyscan` para evitar este problema
- Si persiste, conecta manualmente una vez al servidor

### Error: "Directory not found"
- Verifica que `PROJECT_PATH` sea correcto
- Asegúrate de que el repositorio esté clonado en esa ruta

### Error durante deployment
- Revisa logs en GitHub Actions
- Conecta por SSH y revisa `deployment.log`
- Verifica que `config/private` esté enlazado correctamente

## 🎯 Próximos pasos

Una vez configurado, podrás:
1. Hacer cambios en tu código local
2. `git push` a GitHub
3. Ver cómo se despliega automáticamente
4. Acceder a tus servicios actualizados

¡Tu home server se actualizará automáticamente con cada commit!
