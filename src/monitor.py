"""
Monitor module for AI-SRE-System.
Handles log monitoring from journald or log files.
"""

import subprocess
from typing import Callable, List, Optional
from threading import Thread


class LogMonitor:
    """Log monitor for system errors."""
    
    def __init__(
        self,
        monitor_type: str,
        log_path: Optional[str] = None,
        error_levels: Optional[List[str]] = None,
        error_keywords: Optional[List[str]] = None,
        auto_keywords_file: Optional[str] = None
    ):
        """
        Initialize log monitor.
        
        Args:
            monitor_type: "JOURNAL" or "FILE"
            log_path: Path to log file (for FILE mode)
            error_levels: Error levels to monitor (for JOURNAL mode)
            error_keywords: Keywords to filter (for FILE mode)
            auto_keywords_file: Path to auto-execute keywords file
        """
        self.monitor_type = monitor_type.upper()
        self.log_path = log_path
        self.error_levels = error_levels or ["err", "crit", "alert", "emerg"]
        self.error_keywords = error_keywords or ["ERROR", "CRITICAL", "FATAL"]
        self.auto_keywords_file = auto_keywords_file
        self.auto_keywords = self._load_auto_keywords()
        self.is_running = False
    
    def _load_auto_keywords(self) -> List[str]:
        """
        Load auto-execute keywords from file.
        
        Returns:
            List of keywords (uppercase)
        """
        if not self.auto_keywords_file:
            return []
        
        try:
            with open(self.auto_keywords_file, 'r') as f:
                return [line.strip().upper() for line in f if line.strip()]
        except Exception as e:
            print(f"Warning: Failed to load auto keywords: {e}")
            return []
    
    def reload_auto_keywords(self) -> None:
        """Reload auto-execute keywords from file."""
        self.auto_keywords = self._load_auto_keywords()
    
    def is_auto_execute(self, log_line: str) -> bool:
        """
        Check if log line matches auto-execute keywords.
        
        Args:
            log_line: Log line to check
            
        Returns:
            True if should auto-execute
        """
        log_upper = log_line.upper()
        return any(keyword in log_upper for keyword in self.auto_keywords)
    
    def start(self, callback: Callable[[str, bool], None]) -> None:
        """
        Start monitoring logs.
        
        Args:
            callback: Function to call with (log_line, is_auto_execute)
        """
        self.is_running = True
        
        if self.monitor_type == "JOURNAL":
            self._monitor_journald(callback)
        elif self.monitor_type == "FILE":
            self._monitor_file(callback)
        else:
            raise ValueError(f"Invalid monitor type: {self.monitor_type}")
    
    def _monitor_journald(self, callback: Callable[[str, bool], None]) -> None:
        """Monitor journald logs."""
        # Build error level filter
        level_filter = "..".join([self.error_levels[0], self.error_levels[-1]])
        
        try:
            proc = subprocess.Popen(
                ['journalctl', '-f', '-n', '0', '-p', level_filter],
                stdout=subprocess.PIPE,
                text=True,
                bufsize=1
            )
            
            print(f"[*] Monitoring started (JOURNALD, levels: {level_filter})")
            
            while self.is_running:
                line = proc.stdout.readline()
                if not line:
                    break
                
                line = line.strip()
                if line:
                    is_auto = self.is_auto_execute(line)
                    callback(line, is_auto)
                    
        except Exception as e:
            print(f"Error monitoring journald: {e}")
        finally:
            if proc:
                proc.terminate()
    
    def _monitor_file(self, callback: Callable[[str, bool], None]) -> None:
        """Monitor log file."""
        if not self.log_path:
            raise ValueError("log_path required for FILE monitoring")
        
        try:
            proc = subprocess.Popen(
                ['tail', '-F', '-n', '0', self.log_path],
                stdout=subprocess.PIPE,
                text=True,
                bufsize=1
            )
            
            print(f"[*] Monitoring started (FILE: {self.log_path})")
            
            while self.is_running:
                line = proc.stdout.readline()
                if not line:
                    break
                
                line = line.strip()
                
                # Filter by error keywords
                if not any(keyword in line.upper() for keyword in self.error_keywords):
                    continue
                
                is_auto = self.is_auto_execute(line)
                callback(line, is_auto)
                    
        except Exception as e:
            print(f"Error monitoring file: {e}")
        finally:
            if proc:
                proc.terminate()
    
    def stop(self) -> None:
        """Stop monitoring."""
        self.is_running = False
