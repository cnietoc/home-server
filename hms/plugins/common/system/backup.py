"""
Plugin: system backup
Creates compressed backups of all stack data and configuration.
Data is read/written via a root Docker container to handle files
owned by root that were created by other containers.
"""

import fnmatch
import logging
import os
import shutil
import subprocess
import tarfile
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.paths import get_project_root, get_data_root
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


def _is_excluded(rel: str, is_dir: bool, patterns: List[str]) -> bool:
    """
    Gitignore-style exclusion check.
    rel     : path relative to data/<stack>/, e.g. "traefik/logs/access.log"
    is_dir  : whether the tar member is a directory
    patterns: raw patterns from config (leading/trailing whitespace is stripped here)

    Rules (mirrors gitignore):
    - Trailing /  → only matches directories
    - No /        → matches any path component at any depth (basename rule)
    - Contains /  → matches against the full relative path or any ancestor
    """
    for raw in patterns:
        pat = raw.strip()
        if not pat or pat.startswith("#"):
            continue
        dir_only = pat.endswith("/")
        if dir_only and not is_dir:
            continue
        pat = pat.strip("/")
        if not pat:
            continue
        if "/" not in pat:
            # Basename rule: match against any single component
            for component in rel.split("/"):
                if fnmatch.fnmatch(component, pat):
                    return True
        else:
            # Path rule: match full rel or check if rel lives inside a matched dir
            if fnmatch.fnmatch(rel, pat):
                return True
            parts = rel.split("/")
            for i in range(1, len(parts)):
                if fnmatch.fnmatch("/".join(parts[:i]), pat):
                    return True
    return False


def _fmt_size(b: int) -> str:
    for unit, threshold in (("GB", 1024 ** 3), ("MB", 1024 ** 2), ("KB", 1024)):
        if b >= threshold:
            return f"{b / threshold:.1f} {unit}"
    return f"{b} B"


class BackupPlugin(GlobalPlugin):
    """Create compressed backups of stacks and infra."""

    def __init__(self):
        super().__init__()
        self.project_root = get_project_root()
        self.data_root = get_data_root()
        self.backup_root = self.project_root / "backups"
        self.backup_root.mkdir(exist_ok=True)

    def get_name(self) -> str:
        return "backup"

    def get_description(self) -> str:
        return "Create compressed backups of stacks and infra"

    def get_help(self) -> str:
        return """
Backup - Create and restore compressed backups of stacks and infra

USAGE:
  hms system backup [COMMAND] [OPTIONS]

COMMANDS:
  create  (default)   Create new backups
  restore             Restore from a previous backup
  list                List all available backups

CREATE OPTIONS:
  --dry-run           Only show what would be backed up, without executing
  --stack STACK       Back up only a specific stack (excluding hms)
  --hms-only          Back up only "hms" (infra + config)
  --force             Ignore enabled=false and min_interval in [stack.backups]
  --no-rotate         Do not delete old backups after creating new ones
  -h, --help          Show this help

RESTORE OPTIONS:
  --file FILE         Backup file to restore (e.g. hms_20240219-143000.tar.gz)
  --dry-run           Only show what would be restored, without executing
  -h, --help          Show this help

EXAMPLES - CREATE:
  hms system backup                        # Back up all stacks + hms
  hms system backup create --stack media   # Back up only the media stack
  hms system backup --hms-only             # Back up only hms
  hms system backup --dry-run              # Preview what would be backed up

EXAMPLES - RESTORE:
  hms system backup list                   # List available backups
  hms system backup restore --file hms_20240219-143000.tar.gz    # Restore backup
  hms system backup restore --file media_20240219-143000.tar.gz  # Restore stack
  hms system backup restore --file hms_20240219-143000.tar.gz --dry-run  # Dry run

CONFIGURATION:
  [global.backups]
    max_backups = 5                  # Maximum backups per group (hms, stack)

  [stacks.<stack>.backups]
    enabled = true                   # Enable/disable backup (default: true)
    exclude = ["path/pattern"]        # Patterns to exclude (glob-style)
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
            ui.err(f"Unknown command: {command}")
            print(self.get_help())
            return 1

    # ─── Helpers Docker ──────────────────────────────────────────────────────

    def _get_host_data_root(self) -> str:
        """Path on the HOST to the data/ directory (needed to mount Docker volumes)."""
        host_root = config_manager.get_config_value("global.host_root", "")
        if not host_root:
            raise RuntimeError("global.host_root is not configured")
        return os.path.join(host_root, "data")

    def _backup_dir_via_docker(
        self,
        host_data_root: str,
        stack_name: str,
        exclude_patterns: List[str],
        dest_tar: tarfile.TarFile,
    ) -> dict:
        """
        Create a tar of data/{stack_name}/ using a root Alpine container.
        Streams the output directly to dest_tar to avoid buffering everything in memory.
        Returns a dict with stats: files, bytes, top_files.
        """
        # Exact paths without wildcards → Docker --exclude so large dirs never cross the pipe.
        # Everything is also checked Python-side with gitignore semantics (correct glob/depth).
        docker_exclude_args = []
        for pattern in exclude_patterns:
            pat = pattern.strip().strip("/")
            if pat and not any(c in pat for c in "*?["):
                docker_exclude_args.extend(["--exclude", f"data/{stack_name}/{pat}"])

        cmd = [
            "docker", "run", "--rm",
            "-v", f"{host_data_root}:/data:ro",
            "alpine",
            "tar", "cf", "-", "-C", "/",
        ] + docker_exclude_args + [f"data/{stack_name}"]

        logger.debug(f"   Docker backup: {' '.join(cmd)}")
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        stack_prefix = f"data/{stack_name}/"
        files = 0
        total_bytes = 0
        all_files: List[tuple] = []
        try:
            with tarfile.open(fileobj=proc.stdout, mode="r|") as src_tar:
                for member in src_tar:
                    rel = member.name[len(stack_prefix):] if member.name.startswith(stack_prefix) else ""
                    if rel and _is_excluded(rel, member.isdir(), exclude_patterns):
                        continue  # tarfile streaming auto-advances past skipped data
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
                raise RuntimeError(f"Docker tar failed: {stderr.decode().strip()}")

        all_files.sort(reverse=True)
        return {"files": files, "bytes": total_bytes, "top_files": all_files[:5]}

    def _restore_data_via_docker(
        self,
        src_tar: tarfile.TarFile,
        data_members: List[tarfile.TarInfo],
        host_data_root: str,
    ) -> int:
        """
        Restore the data/* members of a backup using a root Alpine container.
        Preserves original owner, permissions, and timestamps.
        Returns the number of restored files.
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
                f"Docker restore failed (exit {result.returncode}): {result.stderr.decode().strip()}"
            )

        return count

    # ─── Python extraction (config.toml only) ───────────────────────────

    def _extract_member_to(self, tar: tarfile.TarFile, member: tarfile.TarInfo, target_path: Path) -> None:
        """Extract a tar member into target_path preserving permissions."""
        f = tar.extractfile(member)
        if f is not None:
            target_path.parent.mkdir(parents=True, exist_ok=True)
            with open(target_path, "wb") as out:
                shutil.copyfileobj(f, out)
            target_path.chmod(member.mode & 0o777)

    # ─── List ─────────────────────────────────────────────────────────────────

    def _run_list(self, args: List[str]) -> int:
        """List all available backups."""
        if not self.backup_root.exists():
            ui.err("Backup directory does not exist")
            return 1

        backup_files = sorted(self.backup_root.glob("*.tar.gz"), reverse=True)
        if not backup_files:
            ui.info("ℹ️  No backups available")
            return 0

        ui.info(f"📦 Total backups found: {len(backup_files)}\n")

        backup_groups: Dict[str, List[Path]] = {}
        for backup_file in backup_files:
            parts = backup_file.stem.rsplit("_", 1)
            if len(parts) == 2:
                group_name = parts[0]
                backup_groups.setdefault(group_name, []).append(backup_file)

        for group_name in sorted(backup_groups.keys()):
            backups = backup_groups[group_name]
            ui.info(f"📁 {group_name.upper()}")
            for i, backup_file in enumerate(backups):
                size_mb = backup_file.stat().st_size / (1024 * 1024)
                marker = "→" if i == 0 else " "
                ui.info(f"  {marker} {backup_file.name:40s} ({size_mb:8.2f} MB)")

        return 0

    # ─── Restore ──────────────────────────────────────────────────────────────

    def _run_restore(self, args: List[str]) -> int:
        """Restore from a backup."""
        backup_file: Optional[str] = None
        dry_run = False

        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("-h", "--help"):
                print(self.get_help())
                return 0
            elif arg == "--file":
                if i + 1 >= len(args):
                    ui.err("--file requires a value")
                    return 1
                backup_file = args[i + 1]
                i += 2
            elif arg == "--dry-run":
                dry_run = True
                i += 1
            else:
                ui.warn(f"Unknown argument: {arg}")
                i += 1

        if not backup_file:
            ui.err("--file with the backup name is required")
            ui.info("\nTo list available backups:\n  hms system backup list")
            return 1

        backup_path = self.backup_root / backup_file
        if not backup_path.exists():
            ui.err(f"Backup not found: {backup_file}")
            return 1

        ui.info(f"🔄 Restoring backup: {backup_file}")

        try:
            result = self._restore_backup(backup_path, dry_run)
            if result != 0 and not dry_run:
                from hms.lib.notify import send as notify
                notify("❌ HMS: restore failed", f"Backup: {backup_file}")
            return result
        except Exception:
            logger.exception("restore_backup failed for '%s'", backup_file)
            ui.err("Error during restore")
            if not dry_run:
                from hms.lib.notify import send as notify
                notify("❌ HMS: restore failed", f"Backup: {backup_file}")
            return 1

    def _restore_backup(self, backup_path: Path, dry_run: bool = False) -> int:
        """Restore a backup. Data via Docker (root), config.toml via Python."""
        backup_name = backup_path.stem.rsplit("_", 1)[0]
        ui.info(f"\n📋 Analysing backup: {backup_name}")

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
                ui.info("\n[DRY-RUN] Would restore:")
                if has_config:
                    ui.info("   → config.toml (current config would be saved as config.toml.bak)")
                dir_counts: Dict[str, int] = {}
                for m in data_members:
                    if not m.isdir():
                        top = "/".join(m.name.split("/")[:3])
                        dir_counts[top] = dir_counts.get(top, 0) + 1
                for dir_path, count in sorted(dir_counts.items()):
                    ui.info(f"   → {dir_path}/ ({count} files)")
                if stack_targets:
                    ui.info(f"\n[DRY-RUN] Would temporarily stop: {', '.join(stack_targets)}")
                return 0

            host_data_root = self._get_host_data_root()

            # Stop stacks before restoring
            stopped: Dict[str, bool] = {}
            for stack_name in stack_targets:
                was_running = self._stop_stack_for_operation(stack_name)
                if was_running is None:
                    ui.err(f"Could not stop '{stack_name}' for restore")
                    for prev_stack, prev_running in stopped.items():
                        self._start_stack_after_operation(prev_stack, prev_running)
                    return 1
                stopped[stack_name] = was_running

            try:
                # Restore data via Docker (handles root-owned files)
                if data_members:
                    ui.info("\n🐳 Restoring data via Docker...")
                    restored_count = self._restore_data_via_docker(tar, data_members, host_data_root)
                    ui.info(f"   ✅ {restored_count} files restored")

                if config_member:
                    target_path = self.project_root / "config.toml"
                    if target_path.exists():
                        shutil.copy2(target_path, self.project_root / "config.toml.bak")
                        ui.info("   💾 Current config saved as config.toml.bak")
                    self._extract_member_to(tar, config_member, target_path)
                    ui.info("   ✅ Restored: config.toml")

                ui.ok("Restore completed")
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

    def _last_backup_path(self, name: str) -> Optional[Path]:
        """Returns the most recent backup file for `name`, or None."""
        backups = sorted(
            self.backup_root.glob(f"{name}_*.tar.gz"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        return backups[0] if backups else None

    def _hours_since_last_backup(self, name: str) -> Optional[float]:
        """Returns hours since the most recent backup for `name`, or None if none exists."""
        last = self._last_backup_path(name)
        if not last:
            return None
        age = datetime.now() - datetime.fromtimestamp(last.stat().st_mtime)
        return age.total_seconds() / 3600

    def _data_changed_since_backup(self, stack_name: str, backup_path: Path) -> bool:
        """
        Returns True if any file in data/<stack>/ was modified after backup_path was created.
        Short-circuits on the first changed file found. stat() works even on root-owned files
        as long as the parent directory is traversable.
        """
        backup_ts = backup_path.stat().st_mtime
        data_dir = self.data_root / stack_name
        for root, _dirs, files in os.walk(data_dir):
            for fname in files:
                try:
                    if (Path(root) / fname).stat().st_mtime > backup_ts:
                        return True
                except OSError:
                    return True  # can't stat → assume changed
        return False

    def _run_create(self, args: List[str]) -> int:
        """Create new backups."""
        dry_run = False
        specific_stack: Optional[str] = None
        hms_only = False
        force = False
        no_rotate = False

        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("--help", "-h"):
                print(self.get_help())
                return 0
            elif arg == "--stack":
                if i + 1 >= len(args):
                    ui.err("--stack requires a value")
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
                ui.warn(f"Unknown argument: {arg}")
                i += 1

        ui.info("🔄 Starting backup...")

        exit_code = 0
        timestamps = []

        try:
            if not specific_stack or specific_stack == "hms":
                ui.info("\n📦 Creating backup of 'hms' (infra + config)...")
                min_h = self._min_backup_interval_h()
                hours = self._hours_since_last_backup("hms")
                if hours is not None and hours < min_h and not force:
                    ui.info(f"   ⏭️  Skipping (last backup {hours:.1f}h ago, minimum {min_h:.0f}h)")
                elif dry_run:
                    ui.info("   [DRY-RUN] Would create: backups/hms_*.tar.gz")
                    ui.info("   [DRY-RUN] Would temporarily stop: infra")
                else:
                    infra_was_running = self._stop_stack_for_operation("infra")
                    if infra_was_running is None:
                        ui.err("Could not stop 'infra' for backup")
                        exit_code = 1
                    else:
                        try:
                            result = self._create_hms_backup()
                            if result:
                                timestamp, stats = result
                                timestamps.append(("hms", timestamp))
                                self._log_backup_stats("hms", timestamp, stats)
                            else:
                                ui.err("Failed to create 'hms' backup")
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
                        ui.info(f"⏭️  Skipping stack '{stack_name}' (disabled in config)")
                        continue

                    if not (self.data_root / stack_name).exists():
                        ui.info(f"⏭️  Skipping stack '{stack_name}' (data/ does not exist)")
                        continue

                    ui.info(f"\n📦 Creating backup of stack '{stack_name}'...")

                    last_backup = self._last_backup_path(stack_name)
                    if last_backup is not None and not force:
                        hours = (datetime.now() - datetime.fromtimestamp(last_backup.stat().st_mtime)).total_seconds() / 3600
                        if hours < min_h:
                            ui.info(f"   ⏭️  Skipping (last backup {hours:.1f}h ago, minimum {min_h:.0f}h)")
                            continue
                        if not self._data_changed_since_backup(stack_name, last_backup):
                            ui.info(f"   ⏭️  Skipping (no changes since last backup)")
                            continue

                    if dry_run:
                        ui.info(f"   [DRY-RUN] Would create: backups/{stack_name}_*.tar.gz")
                        ui.info(f"   [DRY-RUN] Would temporarily stop: {stack_name}")
                        exclude_patterns = backup_config.get("exclude", [])
                        if exclude_patterns:
                            logger.debug("   [DRY-RUN] Excluyendo: %s", exclude_patterns)
                    else:
                        was_running = self._stop_stack_for_operation(stack_name)
                        if was_running is None:
                            ui.err(f"Could not stop '{stack_name}' for backup")
                            exit_code = 1
                            continue
                        try:
                            result = self._create_stack_backup(stack_name)
                            if result:
                                timestamp, stats = result
                                timestamps.append((stack_name, timestamp))
                                self._log_backup_stats(stack_name, timestamp, stats)
                            else:
                                ui.err(f"Failed to create backup for '{stack_name}'")
                                exit_code = 1
                        finally:
                            if self._start_stack_after_operation(stack_name, was_running) != 0:
                                exit_code = 1

            if not dry_run and not no_rotate:
                ui.info("\n🔄 Rotating old backups...")
                self._rotate_backups()

            if dry_run:
                ui.ok("[DRY-RUN] Simulation completed (no real changes)")
            else:
                ui.ok(f"Backup completed. {len(timestamps)} backup(s) created")

        except Exception:
            logger.exception("backup failed")
            ui.err("Error during backup")
            return 1

        return exit_code

    def _create_hms_backup(self) -> Optional[tuple]:
        """Backup of infra (via Docker) + config.toml (via Python). Returns (timestamp, stats)."""
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
                    ui.warn("data/infra/ does not exist, skipping")

                if config_file.exists():
                    try:
                        tar.add(config_file, arcname="config.toml")
                        cfg_size = config_file.stat().st_size
                        stats["files"] += 1
                        stats["bytes"] += cfg_size
                        stats["top_files"].append((cfg_size, "config.toml"))
                    except (PermissionError, OSError) as e:
                        ui.warn(f"Could not include 'config.toml': {e}")

                self._add_manifest_to_tar(tar, self._create_manifest("hms", []))

            stats["top_files"].sort(reverse=True)
            stats["top_files"] = stats["top_files"][:5]
            stats["compressed_bytes"] = backup_file.stat().st_size
            return timestamp, stats

        except Exception:
            logger.exception("   Error creating hms backup")
            return None

    def _create_stack_backup(self, stack_name: str) -> Optional[tuple]:
        """Backup of a stack via Docker. Returns (timestamp, stats)."""
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

        except Exception:
            logger.exception(f"   Error creating backup for {stack_name}")
            return None

    def _log_backup_stats(self, name: str, timestamp: str, stats: dict) -> None:
        files = stats.get("files", 0)
        raw = stats.get("bytes", 0)
        compressed = stats.get("compressed_bytes", 0)
        top_files = stats.get("top_files", [])

        ui.ok(f"Backup of '{name}' completed: {name}_{timestamp}.tar.gz")
        ui.info(f"   {files} file(s)  ·  {_fmt_size(raw)} uncompressed  →  {_fmt_size(compressed)} on disk")
        if top_files:
            ui.info("   Largest files:")
            for size, fname in top_files:
                ui.info(f"     {_fmt_size(size):>10}  {fname}")

    # ─── Manifest ─────────────────────────────────────────────────────────────

    def _create_manifest(self, name: str, exclude_patterns: List[str]) -> str:
        return f"""BACKUP MANIFEST
===============
Name: {name}
Creation date: {datetime.now().isoformat()}
Exclusion patterns: {exclude_patterns if exclude_patterns else 'none'}
""".strip()

    def _add_manifest_to_tar(self, tar: tarfile.TarFile, manifest_content: str):
        import io
        manifest_bytes = manifest_content.encode("utf-8")
        tarinfo = tarfile.TarInfo(name=".backup-manifest.txt")
        tarinfo.size = len(manifest_bytes)
        tar.addfile(tarinfo, io.BytesIO(manifest_bytes))

    # ─── Rotation ─────────────────────────────────────────────────────────────

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
                    logger.info("rotated out: %s", backup_file.name)

        except Exception:
            logger.exception("Error during backup rotation")

    # ─── Stack lifecycle ───────────────────────────────────────────────────────

    def _start_stack_after_operation(self, stack_name: str, was_running: bool) -> int:
        if not was_running:
            return 0
        ui.info(f"🟢 Restarting stack '{stack_name}'...")
        result = docker_manager.stack_up(stack_name)
        if result == 0:
            ui.ok(f"Stack '{stack_name}' resumed")
        else:
            ui.err(f"Could not resume '{stack_name}'")
        return result

    def _stop_stack_for_operation(self, stack_name: str) -> Optional[bool]:
        current_status = docker_manager.get_stack_status(stack_name)
        if current_status in ["running", "partial"]:
            ui.info(f"🔴 Stopping stack '{stack_name}'...")
            result = docker_manager.stack_down(stack_name)
            if result != 0:
                ui.err(f"Failed to stop '{stack_name}'")
                return None
            return True
        return False
