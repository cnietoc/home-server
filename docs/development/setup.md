# Guía de Desarrollo - HMS

Cómo desarrollar, contribuir y extender HMS.

## 🔧 Setup de Desarrollo

### Requisitos

```bash
# Python 3.11+
python3 --version

# uv (gestor de paquetes)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Docker
docker --version
```

### Instalación Local

```bash
# 1. Clonar repo
git clone <url> ~/hms-dev
cd ~/hms-dev

# 2. Instalar dependencias
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"

# 3. Verificar instalación
python -m hms --help
```

## 📁 Estructura de Desarrollo

```
hms/
├── __main__.py              # Entry point
├── cli/
│   └── cli.py              # CLI Dispatcher
├── core/
│   ├── config.py           # Configuración
│   ├── docker.py           # Docker operations
│   └── plugin.py           # Base plugins
├── lib/
│   ├── stacks.py           # Stack discovery
│   └── plugin_loader.py    # Plugin loading
└── plugins/
    ├── globals/            # Comandos globales
    │   ├── start.py
    │   ├── stop.py
    │   └── list.py
    └── stacks/             # Comandos stack
        ├── up.py
        ├── down.py
        └── info.py
```

## 🧪 Testing

```bash
# Correr tests
pytest

# Con cobertura
pytest --cov=hms

# Tests específicos
pytest tests/test_cli.py -v

# Watch mode
pytest-watch
```

## 📝 Linting y Formato

```bash
# Format código
black hms/

# Lint
ruff check hms/

# Type checking
mypy hms/
```

## 🔌 Crear Nuevo Plugin Global

### Paso 1: Crear archivo

```python
# hms/plugins/globals/mycommand.py
from hms.core.plugin import GlobalPlugin
import logging

logger = logging.getLogger(__name__)

class MyCommandPlugin(GlobalPlugin):
    def run(self, args):
        logger.info("Ejecutando mi comando")
        return 0
```

### Paso 2: El plugin se descubre automáticamente

```bash
hms mycommand
```

## 🔲 Crear Nuevo Plugin de Stack

### Paso 1: Crear archivo

```python
# hms/plugins/stacks/myaction.py
from hms.core.plugin import StackPlugin
import logging

logger = logging.getLogger(__name__)

class MyActionPlugin(StackPlugin):
    def run_stacks(self, stacks, args):
        logger.info(f"Acción en {stacks}")
        return 0
    
    def run_all_stacks(self, args):
        logger.info("Acción en todos los stacks")
        return 0
```

### Paso 2: Usar

```bash
hms infra myaction
hms infra,media myaction
```

## 🚀 Crear Nuevo Stack

### Paso 1: Crear estructura

```bash
mkdir -p stacks/mystack
cd stacks/mystack
```

### Paso 2: docker-compose.yml

```yaml
version: '3.8'

services:
  main:
    image: myimage:latest
    container_name: mystack-main
    ports:
      - "8080:8080"
    volumes:
      - data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.mystack.rule=Host(\`mystack.ejemplo.com\`)"

volumes:
  data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/mystack

x-hms:
  name: mystack
  version: "1.0"
  description: "Mi stack personalizado"
  enabled: false
  services:
    - main
```

### Paso 3: pre-deploy.sh (opcional)

```bash
#!/bin/bash
set -e

STACK_DIR="${STACK_DIR:-.}"
STACK_DATA="${STACK_DATA:-/data/mystack}"

echo "🚀 Configurando mystack..."

# Crear directorios
mkdir -p "$STACK_DATA/config"
mkdir -p "$STACK_DATA/logs"

# Inicializar config si no existe
if [ ! -f "$STACK_DATA/config/app.json" ]; then
    cp "$STACK_DIR/app.json.default" "$STACK_DATA/config/app.json"
fi

echo "✅ mystack ready"
```

### Paso 4: Configurar en config.toml

```toml
[mystack]
enabled = true
# Tus opciones...
```

### Paso 5: Probar

```bash
hms mystack validate
hms mystack up
hms mystack info
hms mystack logs -f
hms mystack down
```

## 🧩 Sistema de Plugins Profundo

### BasePlugin

```python
class BasePlugin(ABC):
    """Base plugin class"""
    @abstractmethod
    def run(self, args: List[str]) -> int:
        """Run plugin, return exit code"""
        pass
```

### StackPlugin

```python
class StackPlugin(BasePlugin):
    """Stack-specific plugin"""
    
    def run_stacks(self, stacks: str, args: List[str]) -> int:
        """Run for specific stack(s)"""
        pass
    
    def run_all_stacks(self, args: List[str]) -> int:
        """Run for all enabled stacks"""
        pass
    
    def run(self, args: List[str]) -> int:
        """Default run (usado si se llama diferente)"""
        pass
```

### GlobalPlugin

```python
class GlobalPlugin(BasePlugin):
    """Global command plugin"""
    
    def run(self, args: List[str]) -> int:
        """Execute command"""
        pass
```

## 🔍 Debugging

```bash
# Modo verbose
hms infra up

# Logs detallados
hms infra logs -f --level debug

# Ver configuración parseada
hms config --json
```
