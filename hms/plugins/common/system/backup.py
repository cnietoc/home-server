"""
Plugin: system backup
Crea backups comprimidos de los datos de todos los stacks y configuración.
Los datos se leen/escriben via un contenedor Docker root para manejar ficheros
propiedad de root creados por otros contenedores.
"""

import logging
import os
import shutil
import subprocess
import tarfile
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from hms.core.plugin import GlobalPlugin
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.paths import get_project_root, get_data_root
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


def _fmt_size(b: int) -> str:
    for unit, threshold in (("GB", 1024 ** 3), ("MB", 1024 ** 2), ("KB", 1024)):
        if b >= threshold:
            return f"{b / threshold:.1f} {unit}"
    return f"{b} B"


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
  --force             Ignorar enabled=false y min_interval en [stack.backups]
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

    # ─── Helpers Docker ──────────────────────────────────────────────────────

    def _get_host_data_root(self) -> str:
        """Ruta en el HOST al directorio data/ (necesaria para montar volúmenes Docker)."""
        host_root = config_manager.get_config_value("global.host_root", "")
        if not host_root:
            raise RuntimeError("global.host_root no está configurado")
        return os.path.join(host_root, "data")

    def _backup_dir_via_docker(
        self,
        host_data_root: str,
        stack_name: str,
        exclude_patterns: List[str],
        dest_tar: tarfile.TarFile,
    ) -> dict:
        """
        Crea un tar del directorio data/{stack_name}/ usando un contenedor Alpine root.
        Streams la salida directamente a dest_tar para evitar bufferizar todo en memoria.
        Devuelve un dict con stats: files, bytes, top_files.
        """
        exclude_args = []
        for pattern in exclude_patterns:
            clean = pattern.strip().strip("/")
            if clean:
                exclude_args.extend(["--exclude", f"data/{stack_name}/{clean}"])

        cmd = [
            "docker", "run", "--rm",
            "-v", f"{host_data_root}:/data:ro",
            "alpine",
            "tar", "cf", "-", "-C", "/",
        ] + exclude_args + [f"data/{stack_name}"]

        logger.debug(f"   Docker backup: {' '.join(cmd)}")
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        files = 0
        total_bytes = 0
        all_files: List[tuple] = []
        try:
            with tarfile.open(fileobj=proc.stdout, mode="r|") as src_tar:
                for member in src_tar:
                    f = src_tar.extractfile(member)
                    dest_tar.addfile(member, f)
                    if not member.isdir():
                        files += 1
                        total_bytes += member.size
                        all_files.append((member.size, member.name))
        finally:
            proc.stdout.close()
            _, stderr = proc.communicate()
            if proc.returncode != 0:
                raise RuntimeError(f"Docker tar falló: {stderr.decode().strip()}")

        all_files.sort(reverse=True)
        return {"files": files, "bytes": total_bytes, "top_files": all_files[:5]}

    def _restore_data_via_docker(
        self,
        src_tar: tarfile.TarFile,
        data_members: List[tarfile.TarInfo],
        host_data_root: str,
    ) -> int:
        """
        Restaura los miembros data/* del backup usando un contenedor Alpine root.
        Preserva owner, permisos y timestamps originales.
        Devuelve el número de ficheros restaurados.
        """
        import io

        # Build tar into memory first to avoid pipe lifecycle issues when
        # streaming directly to a subprocess stdin.
        buf = io.BytesIO()
        count = 0
        with tarfile.open(fileobj=buf, mode="w") as out_tar:
            for member in data_members:
                f = src_tar.extractfile(member)
                if member.isdir():
                    out_tar.addfile(member)
                elif f:
                    out_tar.addfile(member, f)
                    count += 1

        cmd = [
            "docker", "run", "--rm", "-i",
            "-v", f"{host_data_root}:/data",
            "alpine",
            "tar", "xf", "-", "-C", "/",
        ]

        logger.debug(f"   Docker restore: {' '.join(cmd)}")
        result = subprocess.run(cmd, input=buf.getvalue(), capture_output=True)

        if result.returncode != 0:
            raise RuntimeError(
                f"Docker restore falló (exit {result.returncode}): {result.stderr.decode().strip()}"
            )

        return count

    # ─── Extracción Python (solo para config.toml) ───────────────────────────

    def _extract_member_to(self, tar: tarfile.TarFile, member: tarfile.TarInfo, target_path: Path) -> None:
        """Extrae un miembro del tar a target_path preservando permisos."""
        f = tar.extractfile(member)
        if f is not None:
            target_path.parent.mkdir(parents=True, exist_ok=True)
            with open(target_path, "wb") as out:
                shutil.copyfileobj(f, out)
            target_path.chmod(member.mode & 0o777)

    # ─── List ─────────────────────────────────────────────────────────────────

    def _run_list(self, args: List[str]) -> int:
        """Listar todos los backups disponibles."""
        if not self.backup_root.exists():
            logger.info("❌ Directorio de backups no existe")
            return 1

        backup_files = sorted(self.backup_root.glob("*.tar.gz"), reverse=True)
        if not backup_files:
            logger.info("❌ No hay backups disponibles")
            return 0

        logger.info(f"📦 Total de backups encontrados: {len(backup_files)}\n")

        backup_groups: Dict[str, List[Path]] = {}
        for backup_file in backup_files:
            parts = backup_file.stem.rsplit("_", 1)
            if len(parts) == 2:
                group_name = parts[0]
                backup_groups.setdefault(group_name, []).append(backup_file)

        for group_name in sorted(backup_groups.keys()):
            backups = backup_groups[group_name]
            logger.info(f"📁 {group_name.upper()}")
            for i, backup_file in enumerate(backups):
                size_mb = backup_file.stat().st_size / (1024 * 1024)
                marker = "→" if i == 0 else " "
                logger.info(f"  {marker} {backup_file.name:40s} ({size_mb:8.2f} MB)")

        return 0

    # ─── Restore ──────────────────────────────────────────────────────────────

    def _run_restore(self, args: List[str]) -> int:
        """Restaurar desde un backup."""
        backup_file: Optional[str] = None
        dry_run = False

        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("-h", "--help"):
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
            logger.info("\nPara listar backups disponibles:\n  hms system backup list")
            return 1

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

    def _restore_backup(self, backup_path: Path, dry_run: bool = False) -> int:
        """Restaura un backup. Datos via Docker (root), config.toml via Python."""
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

            # require data/STACK/... (3 parts) to avoid empty string from bare "data/" entry
            stack_targets = sorted({
                m.name.split("/", 2)[1]
                for m in members
                if m.name.startswith("data/") and len(m.name.split("/", 2)) > 2
            } - {""})

            data_members = [
                m for m in members
                if m.name.startswith("data/") and m.name != "data/"
            ]
            config_member = next((m for m in members if m.name == "config.toml"), None)

            if dry_run:
                logger.info("\n[DRY-RUN] Se restauraría:")
                if has_config:
                    logger.info("   → config.toml (config actual se guardaría como config.toml.bak)")
                dir_counts: Dict[str, int] = {}
                for m in data_members:
                    if not m.isdir():
                        top = "/".join(m.name.split("/")[:3])
                        dir_counts[top] = dir_counts.get(top, 0) + 1
                for dir_path, count in sorted(dir_counts.items()):
                    logger.info(f"   → {dir_path}/ ({count} archivos)")
                if stack_targets:
                    logger.info(f"\n[DRY-RUN] Se detendría temporalmente: {', '.join(stack_targets)}")
                return 0

            host_data_root = self._get_host_data_root()

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
                # Restaurar datos via Docker (maneja ficheros root)
                if data_members:
                    logger.info(f"\n🐳 Restaurando datos via Docker...")
                    restored_count = self._restore_data_via_docker(tar, data_members, host_data_root)
                    logger.info(f"   ✅ {restored_count} archivos restaurados")

                # Restaurar config.toml via Python (no tiene problemas de permisos)
                if config_member:
                    target_path = self.project_root / "config.toml"
                    if target_path.exists():
                        shutil.copy2(target_path, self.project_root / "config.toml.bak")
                        logger.info("   💾 Config actual guardado como config.toml.bak")
                    self._extract_member_to(tar, config_member, target_path)
                    logger.info("   ✅ Restaurado: config.toml")

                logger.info("\n✅ Restauración completada")
                return 0

            finally:
                for stack_name, was_running in stopped.items():
                    self._start_stack_after_operation(stack_name, was_running)

    # ─── Create ───────────────────────────────────────────────────────────────

    def _min_backup_interval_h(self) -> float:
        """Minimum hours between backups of the same stack, from config (default 12h)."""
        from hms.lib.interval import parse_interval
        backup_config = config_manager.get_global_backup_config()
        interval_str = backup_config.get("min_interval", "12h")
        seconds = parse_interval(str(interval_str))
        return seconds / 3600 if seconds else 12.0

    def _hours_since_last_backup(self, name: str) -> Optional[float]:
        """Returns hours since the most recent backup for `name`, or None if none exists."""
        backups = sorted(
            self.backup_root.glob(f"{name}_*.tar.gz"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        if not backups:
            return None
        age = datetime.now() - datetime.fromtimestamp(backups[0].stat().st_mtime)
        return age.total_seconds() / 3600

    def _run_create(self, args: List[str]) -> int:
        """Crear nuevos backups."""
        dry_run = False
        specific_stack: Optional[str] = None
        hms_only = False
        force = False
        no_rotate = False

        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("--help", "-h"):
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
            if not specific_stack or specific_stack == "hms":
                logger.info("\n📦 Creando backup de 'hms' (infra + config)...")
                min_h = self._min_backup_interval_h()
                hours = self._hours_since_last_backup("hms")
                if hours is not None and hours < min_h and not force:
                    logger.info(f"   ⏭️  Saltando (último backup hace {hours:.1f}h, mínimo {min_h:.0f}h)")
                elif dry_run:
                    logger.info("   [DRY-RUN] Se crearía: backups/hms_*.tar.gz")
                    logger.info("   [DRY-RUN] Se detendría temporalmente: infra")
                else:
                    infra_was_running = self._stop_stack_for_operation("infra")
                    if infra_was_running is None:
                        logger.error("❌ No se pudo detener 'infra' para backup")
                        exit_code = 1
                    else:
                        try:
                            result = self._create_hms_backup()
                            if result:
                                timestamp, stats = result
                                timestamps.append(("hms", timestamp))
                                self._log_backup_stats("hms", timestamp, stats)
                            else:
                                logger.error("❌ Falló crear backup de 'hms'")
                                exit_code = 1
                        finally:
                            if self._start_stack_after_operation("infra", infra_was_running) != 0:
                                exit_code = 1

            if not hms_only:
                stacks_to_backup = (
                    [specific_stack] if specific_stack
                    else [s for s in stack_metadata.list_stacks() if s != "infra"]
                )

                min_h = self._min_backup_interval_h()
                for stack_name in stacks_to_backup:
                    backup_config = config_manager.get_stack_backup_config(stack_name)
                    enabled = backup_config.get("enabled", True)
                    if not enabled and not force:
                        logger.info(f"⏭️  Saltando stack '{stack_name}' (deshabilitado en config)")
                        continue

                    if not config_manager.is_stack_enabled(stack_name) and not force:
                        logger.info(f"⏭️  Saltando stack '{stack_name}' (stack deshabilitado en HMS)")
                        continue

                    if not (self.data_root / stack_name).exists():
                        logger.info(f"⏭️  Saltando stack '{stack_name}' (data/ no existe)")
                        continue

                    logger.info(f"\n📦 Creando backup de stack '{stack_name}'...")

                    hours = self._hours_since_last_backup(stack_name)
                    if hours is not None and hours < min_h and not force:
                        logger.info(f"   ⏭️  Saltando (último backup hace {hours:.1f}h, mínimo {min_h:.0f}h)")
                        continue

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
                            result = self._create_stack_backup(stack_name)
                            if result:
                                timestamp, stats = result
                                timestamps.append((stack_name, timestamp))
                                self._log_backup_stats(stack_name, timestamp, stats)
                            else:
                                logger.error(f"❌ Falló crear backup de '{stack_name}'")
                                exit_code = 1
                        finally:
                            if self._start_stack_after_operation(stack_name, was_running) != 0:
                                exit_code = 1

            if not dry_run and not no_rotate:
                logger.info("\n🔄 Rotando backups antiguos...")
                self._rotate_backups()

            if dry_run:
                logger.info("\n✨ [DRY-RUN] Simulación completada (sin cambios reales)")
            else:
                logger.info(f"\n✨ Backup completado. {len(timestamps)} backup(s) creado(s)")

        except Exception as e:
            logger.error(f"❌ Error durante backup: {e}")
            return 1

        return exit_code

    def _create_hms_backup(self) -> Optional[tuple]:
        """Backup de infra (via Docker) + config.toml (via Python). Devuelve (timestamp, stats)."""
        try:
            host_data_root = self._get_host_data_root()
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup_file = self.backup_root / f"hms_{timestamp}.tar.gz"
            config_file = self.project_root / "config.toml"

            stats: dict = {"files": 0, "bytes": 0, "top_files": []}

            with tarfile.open(backup_file, "w:gz") as tar:
                backup_config = config_manager.get_stack_backup_config("infra")
                exclude_patterns = backup_config.get("exclude", [])

                if (self.data_root / "infra").exists():
                    dir_stats = self._backup_dir_via_docker(host_data_root, "infra", exclude_patterns, tar)
                    stats["files"] += dir_stats["files"]
                    stats["bytes"] += dir_stats["bytes"]
                    stats["top_files"].extend(dir_stats["top_files"])
                else:
                    logger.warning("   ⚠️  data/infra/ no existe, saltando")

                if config_file.exists():
                    try:
                        tar.add(config_file, arcname="config.toml")
                        cfg_size = config_file.stat().st_size
                        stats["files"] += 1
                        stats["bytes"] += cfg_size
                        stats["top_files"].append((cfg_size, "config.toml"))
                    except (PermissionError, OSError) as e:
                        logger.warning(f"      ⚠️  No se pudo incluir 'config.toml': {e}")

                self._add_manifest_to_tar(tar, self._create_manifest("hms", []))

            stats["top_files"].sort(reverse=True)
            stats["top_files"] = stats["top_files"][:5]
            stats["compressed_bytes"] = backup_file.stat().st_size
            return timestamp, stats

        except Exception as e:
            logger.error(f"   Error creando backup de hms: {e}")
            return None

    def _create_stack_backup(self, stack_name: str) -> Optional[tuple]:
        """Backup de un stack via Docker. Devuelve (timestamp, stats)."""
        try:
            host_data_root = self._get_host_data_root()
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup_file = self.backup_root / f"{stack_name}_{timestamp}.tar.gz"
            backup_config = config_manager.get_stack_backup_config(stack_name)
            exclude_patterns = backup_config.get("exclude", [])

            stats: dict = {"files": 0, "bytes": 0, "top_files": []}

            with tarfile.open(backup_file, "w:gz") as tar:
                stats = self._backup_dir_via_docker(host_data_root, stack_name, exclude_patterns, tar)
                self._add_manifest_to_tar(tar, self._create_manifest(stack_name, exclude_patterns))

            stats["compressed_bytes"] = backup_file.stat().st_size
            return timestamp, stats

        except Exception as e:
            logger.error(f"   Error creando backup de {stack_name}: {e}")
            return None

    def _log_backup_stats(self, name: str, timestamp: str, stats: dict) -> None:
        files = stats.get("files", 0)
        raw = stats.get("bytes", 0)
        compressed = stats.get("compressed_bytes", 0)
        top_files = stats.get("top_files", [])

        logger.info(f"✅ Backup de '{name}' completado: {name}_{timestamp}.tar.gz")
        logger.info(f"   {files} fichero(s)  ·  {_fmt_size(raw)} sin comprimir  →  {_fmt_size(compressed)} en disco")
        if top_files:
            logger.info("   Ficheros más grandes:")
            for size, fname in top_files:
                logger.info(f"     {_fmt_size(size):>10}  {fname}")

    # ─── Manifest ─────────────────────────────────────────────────────────────

    def _create_manifest(self, name: str, exclude_patterns: List[str]) -> str:
        return f"""BACKUP MANIFEST
===============
Nombre: {name}
Fecha creación: {datetime.now().isoformat()}
Patrón exclusión: {exclude_patterns if exclude_patterns else 'ninguno'}
""".strip()

    def _add_manifest_to_tar(self, tar: tarfile.TarFile, manifest_content: str):
        import io
        manifest_bytes = manifest_content.encode("utf-8")
        tarinfo = tarfile.TarInfo(name=".backup-manifest.txt")
        tarinfo.size = len(manifest_bytes)
        tar.addfile(tarinfo, io.BytesIO(manifest_bytes))

    # ─── Rotación ─────────────────────────────────────────────────────────────

    def _rotate_backups(self) -> None:
        try:
            backup_config = config_manager.get_global_backup_config()
            max_backups = backup_config.get("max_backups", 5)

            backup_groups: Dict[str, List[Path]] = {}
            for backup_file in sorted(self.backup_root.glob("*.tar.gz")):
                parts = backup_file.stem.rsplit("_", 1)
                if len(parts) == 2:
                    backup_groups.setdefault(parts[0], []).append(backup_file)

            for group_name, backups in backup_groups.items():
                backups.sort(key=lambda p: p.stat().st_mtime, reverse=True)
                for backup_file in backups[max_backups:]:
                    backup_file.unlink()
                    logger.info(f"🗑️  Eliminado: {backup_file.name}")

        except Exception as e:
            logger.error(f"Error durante rotación de backups: {e}")

    # ─── Stack lifecycle ───────────────────────────────────────────────────────

    def _start_stack_after_operation(self, stack_name: str, was_running: bool) -> int:
        if not was_running:
            return 0
        logger.info(f"🟢 Reiniciando stack '{stack_name}'...")
        result = docker_manager.stack_up(stack_name)
        if result == 0:
            logger.info(f"✅ Stack '{stack_name}' reanudado")
        else:
            logger.error(f"❌ No se pudo reanudar '{stack_name}'")
        return result

    def _stop_stack_for_operation(self, stack_name: str) -> Optional[bool]:
        current_status = docker_manager.get_stack_status(stack_name)
        if current_status in ["running", "partial"]:
            logger.info(f"🔴 Deteniendo stack '{stack_name}'...")
            result = docker_manager.stack_down(stack_name)
            if result != 0:
                logger.error(f"❌ Falló detener '{stack_name}'")
                return None
            return True
        return False
