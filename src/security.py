"""
Security module for AI-SRE-System.
Handles command validation and security filtering.
"""

import os
import re
from typing import Tuple, List, Optional
from pathlib import Path


class SecurityFilter:
    """Security filter for validating AI-generated commands."""
    
    def __init__(self, blacklist_file: str):
        """
        Initialize security filter.
        
        Args:
            blacklist_file: Path to blacklist file
        """
        self.blacklist_file = blacklist_file
        self.blacklist = self._load_blacklist()
        
        # Dangerous patterns (regex)
        self.dangerous_patterns = [
            r'rm\s+-rf\s+/',  # Recursive force delete from root
            r':\(\)\{.*\};:',  # Fork bomb
            r'>\s*/dev/sd[a-z]',  # Writing to disk devices
            r'curl.*\|\s*bash',  # Piping curl to bash
            r'wget.*\|\s*sh',  # Piping wget to shell
        ]
    
    def _load_blacklist(self) -> List[str]:
        """
        Load blacklist from file.
        
        Returns:
            List of blacklisted keywords (uppercase)
        """
        if not os.path.exists(self.blacklist_file):
            return []
        
        try:
            with open(self.blacklist_file, 'r') as f:
                return [line.strip().upper() for line in f if line.strip()]
        except Exception as e:
            print(f"Warning: Failed to load blacklist: {e}")
            return []
    
    def reload_blacklist(self) -> None:
        """Reload blacklist from file."""
        self.blacklist = self._load_blacklist()
    
    def is_safe(self, command: str) -> Tuple[bool, Optional[str]]:
        """
        Check if command is safe to execute.
        
        Args:
            command: Command to validate
            
        Returns:
            Tuple of (is_safe, reason_if_unsafe)
        """
        if not command or not command.strip():
            return False, "Empty command"
        
        # Check command length
        if len(command) > 500:
            return False, "Command too long (max 500 characters)"
        
        # Check blacklist keywords
        cmd_upper = command.upper()
        for keyword in self.blacklist:
            if keyword in cmd_upper:
                return False, f"Blacklisted keyword: {keyword}"
        
        # Check dangerous patterns
        for pattern in self.dangerous_patterns:
            if re.search(pattern, command, re.IGNORECASE):
                return False, f"Dangerous pattern detected: {pattern}"
        
        # Check for multiple commands (command chaining)
        if self._has_command_chaining(command):
            return False, "Command chaining detected (;, &&, ||)"
        
        # Check for command substitution
        if self._has_command_substitution(command):
            return False, "Command substitution detected ($(), ``)"
        
        return True, None
    
    def _has_command_chaining(self, command: str) -> bool:
        """
        Check if command contains command chaining operators.
        
        Args:
            command: Command to check
            
        Returns:
            True if command chaining detected
        """
        # Allow semicolons in specific contexts (e.g., for loops)
        # But block simple command chaining
        chaining_patterns = [
            r';\s*\w+',  # Semicolon followed by command
            r'\&\&',  # AND operator
            r'\|\|',  # OR operator
        ]
        
        for pattern in chaining_patterns:
            if re.search(pattern, command):
                return True
        
        return False
    
    def _has_command_substitution(self, command: str) -> bool:
        """
        Check if command contains command substitution.
        
        Args:
            command: Command to check
            
        Returns:
            True if command substitution detected
        """
        # Check for $() or ``
        if '$(' in command or '`' in command:
            return True
        
        return False
    
    def get_risk_level(self, command: str) -> str:
        """
        Assess risk level of command.
        
        Args:
            command: Command to assess
            
        Returns:
            Risk level: "LOW", "MEDIUM", "HIGH", or "CRITICAL"
        """
        is_safe, reason = self.is_safe(command)
        
        if not is_safe:
            return "CRITICAL"
        
        # Check for potentially risky operations
        risky_keywords = ['rm', 'mv', 'chmod', 'chown', 'kill', 'pkill']
        cmd_lower = command.lower()
        
        for keyword in risky_keywords:
            if keyword in cmd_lower:
                return "MEDIUM"
        
        # Check for system modifications
        system_keywords = ['systemctl', 'service', 'iptables', 'ufw']
        for keyword in system_keywords:
            if keyword in cmd_lower:
                return "MEDIUM"
        
        return "LOW"
    
    def sanitize_command(self, command: str) -> str:
        """
        Sanitize command by removing dangerous elements.
        
        Args:
            command: Command to sanitize
            
        Returns:
            Sanitized command
        """
        # Remove leading/trailing whitespace
        command = command.strip()
        
        # Remove backticks (often used in markdown)
        command = command.replace('`', '')
        
        # Take only the first line (in case AI returns multiple lines)
        command = command.split('\n')[0]
        
        return command
