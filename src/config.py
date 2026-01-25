"""
Configuration management module for AI-SRE-System.
Handles loading and validation of configuration from YAML files and environment variables.
"""

import os
import yaml
from typing import Any, Dict
from pathlib import Path


class Config:
    """Configuration manager for the AI-SRE system."""
    
    def __init__(self, config_path: str = "config/config.yaml"):
        """
        Initialize configuration manager.
        
        Args:
            config_path: Path to the YAML configuration file
        """
        self.config_path = config_path
        self.config = self._load_config()
        self._validate_config()
    
    def _load_config(self) -> Dict[str, Any]:
        """
        Load configuration from YAML file and substitute environment variables.
        
        Returns:
            Dictionary containing configuration
        """
        if not os.path.exists(self.config_path):
            raise FileNotFoundError(f"Configuration file not found: {self.config_path}")
        
        with open(self.config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        # Substitute environment variables
        config = self._substitute_env_vars(config)
        return config
    
    def _substitute_env_vars(self, obj: Any) -> Any:
        """
        Recursively substitute environment variables in configuration.
        
        Args:
            obj: Configuration object (dict, list, or string)
            
        Returns:
            Object with environment variables substituted
        """
        if isinstance(obj, dict):
            return {k: self._substitute_env_vars(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [self._substitute_env_vars(item) for item in obj]
        elif isinstance(obj, str) and obj.startswith("${") and obj.endswith("}"):
            env_var = obj[2:-1]
            return os.getenv(env_var, obj)
        return obj
    
    def _validate_config(self) -> None:
        """Validate required configuration fields."""
        required_fields = [
            ("api", "gemini_api_key"),
            ("slack", "webhook_url"),
            ("monitoring", "type"),
        ]
        
        for *path, field in required_fields:
            current = self.config
            for key in path:
                if key not in current:
                    raise ValueError(f"Missing required configuration: {'.'.join(path)}.{field}")
                current = current[key]
            
            if field not in current:
                raise ValueError(f"Missing required configuration: {'.'.join(path)}.{field}")
            
            # Check if environment variable was substituted
            value = current[field]
            if isinstance(value, str) and value.startswith("${"):
                raise ValueError(
                    f"Environment variable not set for: {'.'.join(path)}.{field} = {value}"
                )
    
    def get(self, *keys: str, default: Any = None) -> Any:
        """
        Get configuration value by nested keys.
        
        Args:
            *keys: Nested keys to traverse
            default: Default value if key not found
            
        Returns:
            Configuration value
        """
        current = self.config
        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return default
        return current
    
    def get_file_path(self, *keys: str) -> str:
        """
        Get absolute file path from configuration.
        
        Args:
            *keys: Nested keys to traverse
            
        Returns:
            Absolute file path
        """
        path = self.get(*keys)
        if path is None:
            raise ValueError(f"Configuration path not found: {'.'.join(keys)}")
        
        # Convert to absolute path if relative
        if not os.path.isabs(path):
            # Get project root directory
            project_root = Path(__file__).parent.parent
            path = os.path.join(project_root, path)
        
        return path
    
    def reload(self) -> None:
        """Reload configuration from file."""
        self.config = self._load_config()
        self._validate_config()


# Global configuration instance
_config_instance = None


def get_config(config_path: str = "config/config.yaml") -> Config:
    """
    Get global configuration instance.
    
    Args:
        config_path: Path to configuration file
        
    Returns:
        Config instance
    """
    global _config_instance
    if _config_instance is None:
        _config_instance = Config(config_path)
    return _config_instance
