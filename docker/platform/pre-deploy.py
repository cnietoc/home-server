#!/usr/bin/env python3
"""Pre-deploy para stack platform: configura Samba dinámicamente."""
import os
import sys
from pathlib import Path

from hms.lib.stacks import get_stack_manager


def configure_samba() -> int:
    """Genera configuración de Samba basada en shares de stacks.yml."""
    print("🔧 Configurando Samba dinámicamente...")
    stack_name = "platform"
    stack_manager = get_stack_manager()
    stack_dir = stack_manager.get_stack_docker_dir(stack_name)
    override_file = stack_dir / "docker-compose.override.yml"
    config_dir = stack_manager.get_stack_data_dir(stack_name) / "samba"
    config_dir.mkdir(parents=True, exist_ok=True)
    # Obtener shares de todos los stacks
    all_stacks = stack_manager.list_all_stacks()
    shares_by_stack = {}
    for stack in all_stacks:
        stack_info = stack_manager.get_stack_info(stack['name'])
        shares = stack_info.get('shares', {})
        if shares:
            shares_by_stack[stack['name']] = shares
    if not shares_by_stack:
        print("ℹ️  No hay shares configurados")
        _generate_empty_config(override_file, config_dir)
        return 0
    print(f"📁 Shares encontrados en: {', '.join(shares_by_stack.keys())}")
    # Generar docker-compose.override.yml
    _generate_override(override_file, shares_by_stack, stack_dir)
    # Generar config.yml para crazymax/samba
    _generate_samba_config(config_dir / "config.yml", shares_by_stack)
    print("✅ Samba configurado correctamente")
    return 0


def _generate_override(path: Path, shares: dict, stack_dir: Path):
    """Genera docker-compose.override.yml con volúmenes dinámicos."""
    lines = [
        "# Auto-generado por pre-deploy.py",
        "services:",
        "  samba:",
        "    volumes:",
        "      - ${STACK_DATA}/samba:/config",
    ]
    for stack_name, stack_shares in shares.items():
        for share_name, share_config in stack_shares.items():
            # Resolver ruta real del share
            relative_path = share_config.get('path', '').lstrip('/')
            src_path = get_stack_manager().get_stack_data_dir(stack_name) / relative_path
            exposed = share_config.get('exposed_path', f'/{stack_name}/{share_name}')
            container_path = f"/data{exposed}"
            perms = share_config.get('permissions', 'ro')
            # Ruta relativa desde docker/platform
            rel_from_stack = os.path.relpath(src_path, stack_dir)
            if perms == 'ro':
                lines.append(f"      - {rel_from_stack}:{container_path}:ro")
            else:
                lines.append(f"      - {rel_from_stack}:{container_path}")
    lines.extend([
        "    environment:",
        "      - SAMBA_USERNAME=${{SAMBA_USERNAME:-smbuser}}",
        "      - SAMBA_PASSWORD=${{SAMBA_PASSWORD:-changeme}}",
        "      - SAMBA_WORKGROUP=${{SAMBA_WORKGROUP:-WORKGROUP}}",
    ])
    path.write_text("\n".join(lines) + "\n")
    print(f"  ✅ Generado: {path}")


def _generate_samba_config(path: Path, shares: dict):
    """Genera config.yml para crazymax/samba."""
    lines = [
        "# Auto-generado por pre-deploy.py",
        "auth:",
        "  - user: smbuser",
        "    group: smbuser",
        "    uid: 1000",
        "    gid: 1000",
        "    password: changeme",
        "",
        "global:",
        '  - "force user = smbuser"',
        '  - "force group = smbuser"',
        '  - "workgroup = WORKGROUP"',
        '  - "server string = Home Server"',
        '  - "security = user"',
        "",
        "share:",
    ]
    share_count = 0
    for stack_name, stack_shares in shares.items():
        for share_name, share_config in stack_shares.items():
            exposed = share_config.get('exposed_path', f'/{stack_name}/{share_name}')
            container_path = f"/data{exposed}"
            desc = share_config.get('description', share_name)
            perms = share_config.get('permissions', 'ro')
            readonly = "yes" if perms == "ro" else "no"
            # Nombre del share (sin / al inicio)
            samba_share_name = exposed.lstrip('/').replace('/', '_')
            lines.extend([
                f"  - name: {samba_share_name}",
                f"    path: {container_path}",
                f"    browsable: yes",
                f"    readonly: {readonly}",
                "    guestok: no",
                '    validusers: smbuser',
                f'    comment: "{desc}"',
            ])
            share_count += 1
    path.write_text("\n".join(lines) + "\n")
    print(f"  ✅ Generado: {path} ({share_count} shares)")


def _generate_empty_config(override_file: Path, config_dir: Path):
    """Genera configuración vacía si no hay shares."""
    lines = [
        "# Auto-generado por pre-deploy.py",
        "services:",
        "  samba:",
        "    volumes:",
        "      - ${STACK_DATA}/samba:/config",
        "    environment:",
        "      - SAMBA_USERNAME=${{SAMBA_USERNAME:-smbuser}}",
        "      - SAMBA_PASSWORD=${{SAMBA_PASSWORD:-changeme}}",
        "      - SAMBA_WORKGROUP=${{SAMBA_WORKGROUP:-WORKGROUP}}",
    ]
    override_file.write_text("\n".join(lines) + "\n")
    config_lines = [
        "# Auto-generado por pre-deploy.py",
        "auth:",
        "  - user: smbuser",
        "    group: smbuser",
        "    uid: 1000",
        "    gid: 1000",
        "    password: changeme",
        "",
        "global:",
        '  - "force user = smbuser"',
        '  - "force group = smbuser"',
        '  - "workgroup = WORKGROUP"',
        "",
        "share: []",
    ]
    (config_dir / "config.yml").write_text("\n".join(config_lines) + "\n")


if __name__ == "__main__":
    sys.exit(configure_samba())
