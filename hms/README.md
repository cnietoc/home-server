# HMS - Home Server Management System

Sistema de gestión centralizada para home server containerizado, migrado de bash a Python.

## 🚀 Quick Start (Desarrollo Local)

### Requisitos

- **mise** - Para gestionar versiones de Python
  ```bash
  curl https://mise.run | sh
  ```

- **uv** - Para gestión de dependencias Python
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

### Instalación

```bash
# El wrapper hms-dev se encarga de todo automáticamente
./hms-dev --help
```

La primera vez instalará:
1. Python 3.12 via mise
2. Creará un venv con uv
3. Instalará dependencias

## 📋 Comandos Disponibles

### Stack Actions (aplican a cualquier stack)

```bash
# Ver status de un stack
./hms-dev platform status
./hms-dev media status

# Múltiples stacks
./hms-dev platform,media status

# Todos los stacks
./hms-dev status
```

### Global Commands

```bash
# Listar stacks disponibles
./hms-dev show stacks
```

## 🏗️ Arquitectura

```
hms/
├── core/
│   ├── cli.py          # Dispatcher principal
│   └── plugin.py       # Sistema de plugins
├── plugins/
│   ├── stacks/         # Acciones para stacks (up, down, status, etc)
│   │   └── status.py
│   └── global/         # Comandos globales
│       ├── backup/
│       ├── config/
│       ├── show/
│       │   └── stacks.py
│       └── system/
├── lib/                # Librerías compartidas (próximamente)
└── daemon/             # Daemon 24/7 (próximamente)
```

## 🔧 Desarrollo

### Agregar un nuevo plugin de stack

Crear archivo en `hms/plugins/stacks/`:

```python
from hms.core.plugin import StackPlugin

class MyActionPlugin(StackPlugin):
    def get_name(self) -> str:
        return "myaction"
    
    def get_description(self) -> str:
        return "Mi acción personalizada"
    
    def get_help(self) -> str:
        return "Ayuda detallada..."
    
    def run_for_stack(self, stack_name: str, args: list) -> int:
        print(f"Ejecutando myaction en {stack_name}")
        return 0
```

Uso automático:
```bash
./hms-dev platform myaction
```

### Agregar un nuevo comando global

Crear archivo en `hms/plugins/global/<categoria>/`:

```python
from hms.core.plugin import GlobalPlugin

class MyCommandPlugin(GlobalPlugin):
    # Similar al ejemplo anterior
    pass
```

## 📝 Estado del Proyecto

### ✅ Implementado (Fase 1 - MVP)
- [x] Estructura base de directorios
- [x] Sistema de plugins dinámicos
- [x] Dispatcher CLI
- [x] Plugin: `show stacks`
- [x] Plugin: `status`
- [x] Configuración mise + uv
- [x] Descubrimiento dinámico de stacks

### 🚧 En Progreso
- [ ] Plugin: `up` (deploy)
- [ ] Plugin: `down` (stop)
- [ ] Plugin: `prep` (pre-deploy)
- [ ] Plugin: `logs`
- [ ] Sistema de state management
- [ ] Sistema de locks

### 📅 Próximamente (Fase 2+)
- [ ] Integración OneDrive API
- [ ] Daemon 24/7 + APScheduler
- [ ] Backups automáticos
- [ ] Docker + docker-compose para contenedor HMS

## 🐛 Troubleshooting

### Docker no disponible
Si ves el error `Cannot connect to the Docker daemon`, asegúrate de tener Docker Desktop corriendo.

### Reinstalar dependencias
```bash
rm -rf .venv
./hms-dev --help  # Reinstalará todo
```

## 📚 Referencias

- [Plan de Migración](docs/plan-hmsFinalUX.prompt.md)
- [Plan Original](docs/plan-hmsContainerization.prompt.md)

