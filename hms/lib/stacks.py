"""
Stack discovery and metadata management.
Handles reading config/stacks.yml and discovering stacks from docker/ directory.
"""

from pathlib import Path
from typing import List, Dict, Optional
import yaml

from hms.lib.paths import resolve_project_root


class StackManager:
    """Manages stack discovery and metadata."""

    def __init__(self, project_root: Optional[str] = None):
        """
        Initialize stack manager.

        Args:
            project_root: Root directory of the project
        """
        self.project_root = resolve_project_root(project_root)
        self.docker_dir = self.project_root / "docker"
        self.config_file = self.project_root / "config" / "stacks.yml"
        self._metadata_cache = None

    def _load_metadata(self) -> Dict:
        """
        Load stack metadata from config/stacks.yml.

        Returns:
            Dict with stack metadata (cached after first load)
        """
        if self._metadata_cache is not None:
            return self._metadata_cache

        metadata = {}

        if self.config_file.exists():
            try:
                with open(self.config_file) as f:
                    config = yaml.safe_load(f)
                    if config and 'stacks' in config:
                        metadata = config['stacks']
            except Exception as e:
                # Silently fail - not all installations will have stacks.yml
                pass

        self._metadata_cache = metadata
        return metadata

    def discover_stacks(self) -> List[str]:
        """
        Discover available stacks based on config/stacks.yml only.

        Returns:
            Sorted list of stack names defined in stacks.yml that also have a docker-compose.yml
        """
        metadata = self._load_metadata()
        if not metadata:
            return []

        stacks = []
        for stack_name in metadata.keys():
            stack_dir = self.docker_dir / stack_name
            compose_file = stack_dir / "docker-compose.yml"
            if compose_file.exists():
                stacks.append(stack_name)
        return sorted(stacks)

    def get_stack_info(self, stack_name: str) -> Dict:
        """
        Get metadata for a specific stack.

        Args:
            stack_name: Name of the stack

        Returns:
            Dict with stack info (description, config_files, services, etc.)
        """
        metadata = self._load_metadata()
        stack_metadata = metadata.get(stack_name)

        stack_dir = self.docker_dir / stack_name
        compose_exists = (stack_dir / "docker-compose.yml").exists()
        predeploy_sh_exists = (stack_dir / "pre-deploy.sh").exists()
        predeploy_py_exists = (stack_dir / "pre-deploy.py").exists()
        predeploy_exists = predeploy_sh_exists or predeploy_py_exists

        if stack_metadata is None:
            # Not defined in stacks.yml → treated as non-existent
            return {
                'name': stack_name,
                'description': 'Not defined in stacks.yml',
                'config_files': [],
                'services': {},
                'backups': {},
                'path': str(stack_dir),
                'exists': False,
                'has_compose': compose_exists,
                'has_predeploy': predeploy_exists,
            }

        info = {
            'name': stack_name,
            'description': stack_metadata.get('description', 'No description'),
            'config_files': stack_metadata.get('config_files', []),
            'services': stack_metadata.get('services', {}),
            'backups': stack_metadata.get('backups', {}),
            'shares': stack_metadata.get('shares', {}),
            'path': str(stack_dir),
            'exists': compose_exists,
            'has_compose': compose_exists,
            'has_predeploy': predeploy_exists,
        }

        return info

    def list_all_stacks(self) -> List[Dict]:
        """
        List all available stacks with their metadata (only those defined in stacks.yml).

        Returns:
            List of dicts with stack info
        """
        stack_names = sorted(self._load_metadata().keys())
        return [self.get_stack_info(name) for name in stack_names if self.get_stack_info(name)['has_compose']]

    def stack_exists(self, stack_name: str) -> bool:
        """
        Check if a stack exists (must be defined in stacks.yml).

        Args:
            stack_name: Name of the stack

        Returns:
            True if stack is defined in stacks.yml, False otherwise
        """
        metadata = self._load_metadata()
        return stack_name in metadata

    def get_stack_dir(self, stack_name: str) -> Path:
        """
        Get directory path for a stack.

        Args:
            stack_name: Name of the stack

        Returns:
            Path to stack directory
        """
        return self.docker_dir / stack_name

    def has_predeploy(self, stack_name: str) -> bool:
        """
        Check if stack has a pre-deploy script (.sh or .py).

        Args:
            stack_name: Name of the stack

        Returns:
            True if pre-deploy.sh or pre-deploy.py exists
        """
        if not self.stack_exists(stack_name):
            return False
        stack_dir = self.get_stack_dir(stack_name)
        return (stack_dir / "pre-deploy.sh").exists() or (stack_dir / "pre-deploy.py").exists()

    def get_config_files(self, stack_name: str) -> List[str]:
        """
        Get list of config files needed by a stack.

        Args:
            stack_name: Name of the stack

        Returns:
            List of config file names (e.g., ['cloudflare', 'auth'])
        """
        info = self.get_stack_info(stack_name)
        return info.get('config_files', [])

    def get_services(self, stack_name: str) -> Dict:
        """
        Get services defined in a stack.

        Args:
            stack_name: Name of the stack

        Returns:
            Dict of service definitions
        """
        info = self.get_stack_info(stack_name)
        return info.get('services', {})


# Singleton instance
_stack_manager = None


def get_stack_manager(project_root: Optional[str] = None) -> StackManager:
    """
    Get singleton instance of StackManager.

    Args:
        project_root: Root directory (optional, uses env or default)

    Returns:
        StackManager instance
    """
    global _stack_manager
    if _stack_manager is None:
        _stack_manager = StackManager(project_root)
    return _stack_manager

