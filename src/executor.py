"""
Executor module for AI-SRE-System.
Handles safe command execution with timeout and logging.
"""

import subprocess
from typing import Tuple, Optional


class CommandExecutor:
    """Safe command executor with timeout and result capture."""
    
    def __init__(self, timeout: int = 15):
        """
        Initialize command executor.
        
        Args:
            timeout: Command execution timeout in seconds
        """
        self.timeout = timeout
    
    def execute(self, command: str) -> Tuple[bool, str]:
        """
        Execute command safely.
        
        Args:
            command: Command to execute
            
        Returns:
            Tuple of (success, output/error)
        """
        if not command or not command.strip():
            return False, "Empty command"
        
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            
            # Return stdout if available, otherwise stderr
            output = result.stdout if result.stdout else result.stderr
            
            # Consider command successful if return code is 0
            success = result.returncode == 0
            
            return success, output.strip()
            
        except subprocess.TimeoutExpired:
            return False, f"Command timed out after {self.timeout} seconds"
        except Exception as e:
            return False, f"Execution error: {str(e)}"
    
    def execute_with_validation(
        self,
        command: str,
        security_filter
    ) -> Tuple[bool, str, Optional[str]]:
        """
        Execute command with security validation.
        
        Args:
            command: Command to execute
            security_filter: SecurityFilter instance
            
        Returns:
            Tuple of (success, output, error_reason)
        """
        # Validate command safety
        is_safe, reason = security_filter.is_safe(command)
        
        if not is_safe:
            return False, "", f"Security check failed: {reason}"
        
        # Execute command
        success, output = self.execute(command)
        
        return success, output, None
