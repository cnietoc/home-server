"""
Plugin: system backup
Crea backups comprimidos de los datos de todos los stacks y configuración.
"""

import logging
import tarfile
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Dict
import fnmatch
import shutil

from hms.core.plugin import GlobalPlugin
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.paths import get_project_root, get_data_root
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class BackupPlugin(GlobalPlugin):
    """Crear backups comprimidos de stacks e infra."""

    def __init__(self):
        super().__init__()
        self.project_root = get_project_root()
        self.data_root = get_data_root()
        self.backup_root = self.project_root / "backups"
        self.backup_root.mkdir(exist_ok=True)

    def get_name(self) -> str:
        return "backup"

    def get_description(self) -> str:
        return "Crear backups comprimidos de stacks e infra"

    def get_help(self) -> str:
        return """
Backup - Crear y restaurar backups comprimidos de stacks e infra

USAGE:
  hms system backup [COMMAND] [OPTIONS]

COMMANDS:
  create  (default)   Crear nuevos backups
  restore             Restaurar desde un backup anterior
  list                Listar todos los backups disponibles

CREATE OPTIONS:
  --dry-run           Solo mostrar qué se backuparía sin ejecutar
  --stack STACK       Hacer backup solo de un stack específico (excluyendo hms)
  --hms-only          Solo hacer backup de "hms" (infra + config)
  --force             Ignorar enabled=false en [stack.backups] (excepto hms)
  --no-rotate         No eliminar backups antiguos después de crear los nuevos
  -h, --help          Mostrar esta ayuda

RESTORE OPTIONS:
  --file FILE         Archivo backup a restaurar (ej: hms_20240219-143000.tar.gz)
  --dry-run           Solo mostrar qué se restauraría sin ejecutar
  -h, --help          Mostrar esta ayuda

EXAMPLES - CREATE:
  hms system backup                        # Backup de todos los stacks + hms
  hms system backup create --stack media   # Solo backup de stack media
  hms system backup --hms-only             # Solo backup de hms
  hms system backup --dry-run              # Ver qué se backuparía

EXAMPLES - RESTORE:
  hms system backup list                   # Listar backups disponibles
  hms system backup restore --file hms_20240219-143000.tar.gz    # Restaurar backup
  hms system backup restore --file media_20240219-143000.tar.gz  # Restaurar stack
  hms system backup restore --file hms_20240219-143000.tar.gz --dry-run  # Simular

CONFIGURATION:
  [global.backups]
    max_backups = 5                  # Máximo de backups por grupo (hms, stack)
  
  [stacks.<stack>.backups]
    enabled = true                   # Habilitar/deshabilitar backup (default: true)
    exclude = ["path/pattern"]        # Patterns a excluir (globales)
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        # Detectar comando
        command = "create"
        if args and not args[0].startswith("--"):
            command = args[0]
            args = args[1:]

        if command == "create":
            return self._run_create(args)
        elif command == "restore":
            return self._run_restore(args)
        elif command == "list":
            return self._run_list(args)
        else:
            logger.error(f"❌ Comando desconocido: {command}")
            logger.info(self.get_help())
            return 1

    def _run_list(self, args: List[str]) -> int:
        """Listar todos los backups disponibles."""
        # Parsear argumentos
        i = 0
        while i < len(args):
            arg = args[i]
            if arg == "-h" or arg == "--help":
                logger.info("Listar backups disponibles")
                return 0
            i += 1

        if not self.backup_root.exists():
            logger.info("❌ Directorio de backups no existe")
            return 1

        backup_files = sorted(self.backup_root.glob("*.tar.gz"), reverse=True)

        if not backup_files:
            logger.info("❌ No hay backups disponibles")
            return 0

        logger.info(f"📦 Total de backups encontrados: {len(backup_files)}\n")

        # Agrupar por tipo
        backup_groups: Dict[str, List[Path]] = {}
        for backup_file in backup_files:
            parts = backup_file.stem.rsplit("_", 1)
            if len(parts) == 2:
                group_name = parts[0]
                if group_name not in backup_groups:
                    backup_groups[group_name] = []
                backup_groups[group_name].append(backup_file)

        # Mostrar por grupo
        for group_name in sorted(backup_groups.keys()):
            backups = backup_groups[group_name]
            logger.info(f"📁 {group_name.upper()}")
            for i, backup_file in enumerate(backups):
                size_mb = backup_file.stat().st_size / (1024 * 1024)
                timestamp = backup_file.stem.split("_", 1)[1] if "_" in backup_file.stem else "unknown"
                marker = "→" if i == 0 else " "
                logger.info(f"  {marker} {backup_file.name:40s} ({size_mb:8.2f} MB)")

                if logger.isEnabledFor(logging.DEBUG):
                    try:
                        with tarfile.open(backup_file, "r:gz") as tar:
                            file_count = len(tar.getmembers())
                            logger.debug(f"      Archivos: {file_count}")
                    except Exception as e:
                        logger.debug(f"      Error leyendo: {e}")

        return 0

    def _run_restore(self, args: List[str]) -> int:
        """Restaurar desde un backup."""
        # Parsear argumentos
        backup_file: Optional[str] = None
        dry_run = False

        i = 0
        while i < len(args):
            arg = args[i]

            if arg == "-h" or arg == "--help":
                logger.info(self.get_help())
                return 0
            elif arg == "--file":
                if i + 1 >= len(args):
                    logger.error("❌ --file requiere un valor")
                    return 1
                backup_file = args[i + 1]
                i += 2
            elif arg == "--dry-run":
                dry_run = True
                i += 1
            else:
                logger.warning(f"⚠️  Argumento desconocido: {arg}")
                i += 1

        if not backup_file:
            logger.error("❌ Se requiere --file con nombre del backup")
            logger.info("\nPara listar backups disponibles:")
            logger.info("  hms system backup list")
            return 1

        # Verificar que el archivo existe
        backup_path = self.backup_root / backup_file
        if not backup_path.exists():
            logger.error(f"❌ Backup no encontrado: {backup_file}")
            return 1

        logger.info(f"🔄 Restaurando backup: {backup_file}")

        try:
            result = self._restore_backup(backup_path, dry_run)
            if result != 0 and not dry_run:
                from hms.lib.notify import send as notify
                notify("❌ HMS: restore fallido", f"Backup: {backup_file}")
            return result
        except Exception as e:
            logger.error(f"❌ Error durante restauración: {e}")
            if not dry_run:
                from hms.lib.notify import send as notify
                notify("❌ HMS: restore fallido", f"Backup: {backup_file}\nError: {e}")
            return 1

    def _run_create(self, args: List[str]) -> int:
        """Crear nuevos backups."""
        # Parsear argumentos
        dry_run = False
        specific_stack: Optional[str] = None
        hms_only = False
        force = False
        no_rotate = False

        i = 0
        while i < len(args):
            arg = args[i]

            if arg == "--help" or arg == "-h":
                logger.info(self.get_help())
                return 0
            elif arg == "--stack":
                if i + 1 >= len(args):
                    logger.error("❌ --stack requiere un valor")
                    return 1
                specific_stack = args[i + 1]
                i += 2
            elif arg == "--dry-run":
                dry_run = True
                i += 1
            elif arg == "--hms-only":
                hms_only = True
                i += 1
            elif arg == "--force":
                force = True
                i += 1
            elif arg == "--no-rotate":
                no_rotate = True
                i += 1
            else:
                logger.warning(f"⚠️  Argumento desconocido: {arg}")
                i += 1

        logger.info("🔄 Iniciando backup...")

        exit_code = 0
        timestamps = []

        try:
            # Backup de "hms" (infra + config.toml)
            if not specific_stack or specific_stack == "hms":
                logger.info("\n📦 Creando backup de 'hms' (infra + config)...")
                if dry_run:
                    logger.info("   [DRY-RUN] Se crearía: backups/hms_*.tar.gz")
                    logger.info("   [DRY-RUN] Se detendría temporalmente: infra")
                else:
                    infra_was_running = self._stop_stack_for_operation("infra")
                    if infra_was_running is None:
                        logger.error("❌ No se pudo detener 'infra' para backup")
                        exit_code = 1
                    else:
                        try:
                            timestamp = self._create_hms_backup()
                            if timestamp:
                                timestamps.append(("hms", timestamp))
                                logger.info(f"✅ Backup de 'hms' completado: hms_{timestamp}.tar.gz")
                            else:
                                logger.error("❌ Falló crear backup de 'hms'")
                                exit_code = 1
                        finally:
                            restart_result = self._start_stack_after_operation("infra", infra_was_running)
                            if restart_result != 0:
                                exit_code = 1

            # Backups de stacks individuales
            if not hms_only:
                if specific_stack:
                    # Backup de un stack específico
                    stacks_to_backup = [specific_stack]
                else:
                    # Backup de todos los stacks habilitados (excepto infra)
                    all_stacks = stack_metadata.list_stacks()
                    stacks_to_backup = [s for s in all_stacks if s != "infra"]

                for stack_name in stacks_to_backup:
                    backup_config = config_manager.get_stack_backup_config(stack_name)

                    # Verificar si está habilitado
                    enabled = backup_config.get("enabled", True)
                    if not enabled and not force:
                        logger.info(f"⏭️  Saltando stack '{stack_name}' (deshabilitado en config)")
                        continue

                    logger.info(f"\n📦 Creando backup de stack '{stack_name}'...")

                    if dry_run:
                        logger.info(f"   [DRY-RUN] Se crearía: backups/{stack_name}_*.tar.gz")
                        logger.info(f"   [DRY-RUN] Se detendría temporalmente: {stack_name}")
                        exclude_patterns = backup_config.get("exclude", [])
                        if exclude_patterns:
                            logger.debug(f"   [DRY-RUN] Excluyendo: {exclude_patterns}")
                    else:
                        was_running = self._stop_stack_for_operation(stack_name)
                        if was_running is None:
                            logger.error(f"❌ No se pudo detener '{stack_name}' para backup")
                            exit_code = 1
                            continue
                        try:
                            timestamp = self._create_stack_backup(stack_name)
                            if timestamp:
                                timestamps.append((stack_name, timestamp))
                                logger.info(f"✅ Backup de '{stack_name}' completado: {stack_name}_{timestamp}.tar.gz")
                            else:
                                logger.error(f"❌ Falló crear backup de '{stack_name}'")
                                exit_code = 1
                        finally:
                            restart_result = self._start_stack_after_operation(stack_name, was_running)
                            if restart_result != 0:
                                exit_code = 1

            # Rotación de backups
            if not dry_run and not no_rotate:
                logger.info("\n🔄 Rotando backups antiguos...")
                self._rotate_backups()

            # Resumen
            if dry_run:
                logger.info("\n✨ [DRY-RUN] Simulación completada (sin cambios reales)")
            else:
                logger.info(f"\n✨ Backup completado. {len(timestamps)} backup(s) creado(s)")

        except Exception as e:
            logger.error(f"❌ Error durante backup: {e}")
            return 1

        return exit_code

    def _extract_member_to(self, tar: tarfile.TarFile, member: tarfile.TarInfo, target_path: Path) -> None:
        """Extrae un miembro del tar a target_path preservando permisos."""
        f = tar.extractfile(member)
        if f is not None:
            target_path.parent.mkdir(parents=True, exist_ok=True)
            with open(target_path, "wb") as out:
                shutil.copyfileobj(f, out)
            # Preservar permisos originales del archivo
            target_path.chmod(member.mode & 0o777)

    def _restore_backup(self, backup_path: Path, dry_run: bool = False) -> int:
        """
        Restaura un backup específico.

        Determina si es backup de hms o de un stack y restaura en los directorios correspondientes.
        """
        try:
            backup_name = backup_path.stem.rsplit("_", 1)[0]
            logger.info(f"\n📋 Analizando backup: {backup_name}")

            with tarfile.open(backup_path, "r:gz") as tar:
                members = tar.getmembers()
                has_config = any(m.name == "config.toml" for m in members)
                has_infra = any(m.name.startswith("data/infra/") for m in members)
                has_stack_data = any(
                    m.name.startswith("data/") and not m.name.startswith("data/infra/")
                    for m in members
                )

                # Fix: require 3 parts (data/STACK/...) to avoid empty string from bare "data/" entry
                stack_targets = sorted({
                    m.name.split("/", 2)[1]
                    for m in members
                    if m.name.startswith("data/") and len(m.name.split("/", 2)) > 2
                } - {""})

                logger.debug(f"   Config incluido: {has_config}")
                logger.debug(f"   Infra incluido: {has_infra}")
                logger.debug(f"   Data de stack: {has_stack_data}")
                if stack_targets:
                    logger.debug(f"   Stacks detectados: {', '.join(stack_targets)}")

                if dry_run:
                    logger.info("\n[DRY-RUN] Se restauraría:")
                    if has_config:
                        logger.info("   → config.toml (config actual se guardaría como config.toml.bak)")
                    # Mostrar resumen por directorio, no fichero a fichero
                    dir_counts: Dict[str, int] = {}
                    for m in members:
                        if m.name.startswith("data/") and m.isfile():
                            top = "/".join(m.name.split("/")[:3])
                            dir_counts[top] = dir_counts.get(top, 0) + 1
                    for dir_path, count in sorted(dir_counts.items()):
                        logger.info(f"   → {dir_path}/ ({count} archivos)")
                    if stack_targets:
                        logger.info(f"\n[DRY-RUN] Se detendría temporalmente: {', '.join(stack_targets)}")
                    return 0

                # Detener stacks antes de restaurar
                stopped: Dict[str, bool] = {}
                for stack_name in stack_targets:
                    was_running = self._stop_stack_for_operation(stack_name)
                    if was_running is None:
                        logger.error(f"❌ No se pudo detener '{stack_name}' para restauración")
                        for prev_stack, prev_running in stopped.items():
                            self._start_stack_after_operation(prev_stack, prev_running)
                        return 1
                    stopped[stack_name] = was_running

                try:
                    restored_count = 0
                    errors = []
                    logger.info(f"\n🔄 Restaurando archivos...")

                    for member in members:
                        if member.name == ".backup-manifest.txt":
                            continue
                        if member.isdir():
                            continue

                        try:
                            if member.name == "config.toml":
                                target_path = self.project_root / "config.toml"
                                # Fix: backup existing config before overwriting
                                if target_path.exists():
                                    bak_path = self.project_root / "config.toml.bak"
                                    shutil.copy2(target_path, bak_path)
                                    logger.info("   💾 Config actual guardado como config.toml.bak")
                                self._extract_member_to(tar, member, target_path)
                                restored_count += 1
                                logger.info(f"   ✅ Restaurado: {member.name}")

                            elif member.name.startswith("data/"):
                                target_path = self.project_root / member.name
                                self._extract_member_to(tar, member, target_path)
                                restored_count += 1

                        except Exception as e:
                            errors.append(f"{member.name}: {e}")
                            logger.error(f"   ❌ Error restaurando {member.name}: {e}")

                    if errors:
                        logger.error(f"\n⚠️  Restauración parcial: {restored_count} ok, {len(errors)} errores")
                        for err in errors:
                            logger.error(f"   - {err}")
                        return 1

                    logger.info(f"\n✅ Restauración completada: {restored_count} archivos restaurados")
                    return 0

                finally:
                    for stack_name, was_running in stopped.items():
                        self._start_stack_after_operation(stack_name, was_running)

        except Exception as e:
            logger.error(f"❌ Error restaurando backup: {e}")
            return 1

    def _create_hms_backup(self) -> Optional[str]:
        """
        Crea backup de infra + config.toml.

        Retorna el timestamp usado (YYYYMMDD-HHMMSS) o None si falla.
        """
        try:
            # Preparar rutas
            infra_data_dir = self.data_root / "infra"
            config_file = self.project_root / "config.toml"
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup_file = self.backup_root / f"hms_{timestamp}.tar.gz"

            # Crear tar.gz
            with tarfile.open(backup_file, "w:gz") as tar:
                # Añadir infra/
                if infra_data_dir.exists():
                    backup_config = config_manager.get_stack_backup_config("infra")
                    exclude_patterns = backup_config.get("exclude", [])

                    logger.debug("   Incluyendo: data/infra/")
                    if exclude_patterns:
                        logger.debug(f"   Excluyendo patterns: {exclude_patterns}")

                    self._add_dir_to_tar(tar, infra_data_dir, "data/infra", exclude_patterns)

                # Añadir config.toml
                if config_file.exists():
                    logger.debug("   Incluyendo: config.toml")
                    try:
                        tar.add(config_file, arcname="config.toml")
                    except (PermissionError, OSError) as e:
                        logger.warning(f"      ⚠️  No se pudo incluir 'config.toml': {e}")

                # Crear manifest
                manifest = self._create_manifest("hms", [])
                self._add_manifest_to_tar(tar, manifest)

            return timestamp

        except Exception as e:
            logger.error(f"   Error creando backup de hms: {e}")
            return None

    def _create_stack_backup(self, stack_name: str) -> Optional[str]:
        """
        Crea backup de un stack específico.

        Retorna el timestamp usado (YYYYMMDD-HHMMSS) o None si falla.
        """
        try:
            # Preparar rutas
            stack_data_dir = self.data_root / stack_name
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup_file = self.backup_root / f"{stack_name}_{timestamp}.tar.gz"

            # Obtener configuración de exclusiones
            backup_config = config_manager.get_stack_backup_config(stack_name)
            exclude_patterns = backup_config.get("exclude", [])

            if not stack_data_dir.exists():
                logger.warning(f"   ⚠️  Directorio de datos no existe: data/{stack_name}/")
                # Crear backup vacío pero válido
                with tarfile.open(backup_file, "w:gz") as tar:
                    manifest = self._create_manifest(stack_name, exclude_patterns)
                    self._add_manifest_to_tar(tar, manifest)
                return timestamp

            logger.debug(f"   Incluyendo: data/{stack_name}/")
            if exclude_patterns:
                logger.debug(f"   Excluyendo patterns: {exclude_patterns}")

            # Crear tar.gz
            with tarfile.open(backup_file, "w:gz") as tar:
                self._add_dir_to_tar(tar, stack_data_dir, f"data/{stack_name}", exclude_patterns)

                # Crear manifest
                manifest = self._create_manifest(stack_name, exclude_patterns)
                self._add_manifest_to_tar(tar, manifest)

            return timestamp

        except Exception as e:
            logger.error(f"   Error creando backup de {stack_name}: {e}")
            return None

    def _add_dir_to_tar(self, tar: tarfile.TarFile, source_dir: Path, arcname_prefix: str,
                        exclude_patterns: List[str]):
        """
        Añade un directorio al tar, respetando patrones de exclusión.
        Ignora archivos que no se pueden leer (permisos insuficientes, etc.)
        """
        for item in source_dir.rglob("*"):
            if item.is_dir():
                continue  # tarfile añade dirs automáticamente

            # Calcular ruta relativa
            rel_path = item.relative_to(source_dir)
            rel_path_str = str(rel_path)

            # Verificar si coincide con exclusión
            if self._matches_exclude_patterns(rel_path_str, exclude_patterns):
                logger.debug(f"      [EXCLUIDO] {rel_path_str}")
                continue

            # Añadir al tar, ignorando archivos que no se pueden leer
            try:
                arcname = f"{arcname_prefix}/{rel_path_str}"
                tar.add(item, arcname=arcname)
            except (PermissionError, OSError) as e:
                logger.warning(f"      ⚠️  No se pudo incluir '{rel_path_str}': {e}")
                continue

    def _matches_exclude_patterns(self, path: str, patterns: List[str]) -> bool:
        """
        Verifica si una ruta coincide con algún patrón de exclusión (subconjunto estilo .gitignore).
        """
        norm_path = path.replace("\\", "/").lstrip("./")
        parts = [p for p in norm_path.split("/") if p]

        for raw_pattern in patterns:
            pattern = raw_pattern.strip()
            if not pattern or pattern.startswith("#"):
                continue

            anchored = pattern.startswith("/")
            pattern = pattern.lstrip("/")
            dir_only = pattern.endswith("/")
            if dir_only:
                pattern = pattern.rstrip("/")

            if not pattern:
                continue

            # Sin slash: aplica a cualquier segmento (o solo raiz si es anchored).
            if "/" not in pattern:
                if anchored:
                    if parts and fnmatch.fnmatch(parts[0], pattern):
                        return True
                else:
                    if any(fnmatch.fnmatch(part, pattern) for part in parts):
                        return True
                continue

            # Con slash: comparar contra ruta completa (anchored) o cualquier subruta.
            candidates = [norm_path] if anchored else [
                "/".join(parts[i:]) for i in range(len(parts))
            ]

            for candidate in candidates:
                if not dir_only:
                    if fnmatch.fnmatch(candidate, pattern):
                        return True
                    continue

                # Patrones de directorio: coinciden si cualquier prefijo de directorio encaja.
                if fnmatch.fnmatch(candidate, pattern):
                    return True
                candidate_parts = [p for p in candidate.split("/") if p]
                for i in range(1, len(candidate_parts)):
                    dir_prefix = "/".join(candidate_parts[:i])
                    if fnmatch.fnmatch(dir_prefix, pattern):
                        return True

        return False

    def _create_manifest(self, name: str, exclude_patterns: List[str]) -> str:
        """
        Crea un manifest con detalles del backup.
        """
        timestamp = datetime.now().isoformat()
        manifest = f"""
BACKUP MANIFEST
===============
Nombre: {name}
Fecha creación: {timestamp}
Patrón exclusión: {exclude_patterns if exclude_patterns else 'ninguno'}

Este archivo documenta los detalles de la creación del backup.
"""
        return manifest.strip()

    def _add_manifest_to_tar(self, tar: tarfile.TarFile, manifest_content: str):
        """
        Añade el manifest al tar.
        """
        import io
        manifest_bytes = manifest_content.encode("utf-8")
        tarinfo = tarfile.TarInfo(name=".backup-manifest.txt")
        tarinfo.size = len(manifest_bytes)
        tar.addfile(tarinfo, io.BytesIO(manifest_bytes))

    def _rotate_backups(self) -> None:
        """
        Elimina backups antiguos manteniendo max_backups por grupo.
        """
        try:
            backup_config = config_manager.get_global_backup_config()
            max_backups = backup_config.get("max_backups", 5)

            # Agrupar backups por nombre
            backup_groups: Dict[str, List[Path]] = {}

            for backup_file in sorted(self.backup_root.glob("*.tar.gz")):
                # Extraer nombre (ej: "hms", "media", "home" de "media_20240101-120000.tar.gz")
                parts = backup_file.stem.rsplit("_", 1)  # Quitar .tar.gz y último _TIMESTAMP
                if len(parts) == 2:
                    group_name = parts[0]
                    if group_name not in backup_groups:
                        backup_groups[group_name] = []
                    backup_groups[group_name].append(backup_file)

            # Rotar cada grupo
            for group_name, backups in backup_groups.items():
                # Ordenar por modificación (más nuevos primero)
                backups.sort(key=lambda p: p.stat().st_mtime, reverse=True)

                # Eliminar los más antiguos si excede max_backups
                if len(backups) > max_backups:
                    to_delete = backups[max_backups:]
                    for backup_file in to_delete:
                        logger.debug(f"   Eliminando backup antiguo: {backup_file.name}")
                        backup_file.unlink()
                        logger.info(f"🗑️  Eliminado: {backup_file.name}")

        except Exception as e:
            logger.error(f"Error durante rotación de backups: {e}")

    def _start_stack_after_operation(self, stack_name: str, was_running: bool) -> int:
        """Reanuda un stack solo si estaba en ejecución antes de la operación."""
        if not was_running:
            logger.debug(f"   ℹ️  '{stack_name}' ya estaba detenido, no se reinicia")
            return 0

        logger.info(f"🟢 Reiniciando stack '{stack_name}'...")
        result = docker_manager.stack_up(stack_name)
        if result == 0:
            logger.info(f"✅ Stack '{stack_name}' reanudado")
        else:
            logger.error(f"❌ No se pudo reanudar '{stack_name}'")
        return result

    def _stop_stack_for_operation(self, stack_name: str) -> Optional[bool]:
        """Detiene el stack si está en ejecución; retorna si estaba ejecutándose."""
        current_status = docker_manager.get_stack_status(stack_name)
        logger.debug(f"   Estado actual de '{stack_name}': {current_status}")
        if current_status in ["running", "partial"]:
            logger.info(f"🔴 Deteniendo stack '{stack_name}'...")
            result = docker_manager.stack_down(stack_name)
            if result != 0:
                logger.error(f"❌ Falló detener '{stack_name}'")
                return None
            return True

        logger.debug(f"ℹ️  Stack '{stack_name}' no estaba en ejecución")
        return False
