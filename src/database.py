"""
Database module for AI-SRE-System.
Handles incident storage and retrieval using SQLite.
"""

import sqlite3
import json
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from pathlib import Path


class IncidentDatabase:
    """Database manager for incident tracking."""
    
    def __init__(self, db_path: str):
        """
        Initialize database.
        
        Args:
            db_path: Path to SQLite database file
        """
        self.db_path = db_path
        
        # Create directory if it doesn't exist
        db_dir = Path(db_path).parent
        db_dir.mkdir(parents=True, exist_ok=True)
        
        self._init_db()
    
    def _init_db(self) -> None:
        """Initialize database schema."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create incidents table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS incidents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                log_line TEXT NOT NULL,
                ai_command TEXT NOT NULL,
                is_auto_executed BOOLEAN DEFAULT 0,
                is_executed BOOLEAN DEFAULT 0,
                execution_result TEXT,
                execution_timestamp TIMESTAMP,
                is_safe BOOLEAN DEFAULT 1,
                risk_level TEXT,
                error_message TEXT
            )
        ''')
        
        # Create index on timestamp for faster queries
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_timestamp 
            ON incidents(timestamp)
        ''')
        
        conn.commit()
        conn.close()
    
    def add_incident(
        self,
        log_line: str,
        ai_command: str,
        is_auto_executed: bool = False,
        is_safe: bool = True,
        risk_level: str = "LOW",
        error_message: Optional[str] = None
    ) -> int:
        """
        Add new incident to database.
        
        Args:
            log_line: Original log line that triggered the incident
            ai_command: AI-generated command
            is_auto_executed: Whether command was auto-executed
            is_safe: Whether command passed security checks
            risk_level: Risk level of the command
            error_message: Error message if any
            
        Returns:
            Incident ID
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO incidents 
            (log_line, ai_command, is_auto_executed, is_safe, risk_level, error_message)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (log_line, ai_command, is_auto_executed, is_safe, risk_level, error_message))
        
        incident_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        return incident_id
    
    def update_execution(
        self,
        incident_id: int,
        execution_result: str,
        is_executed: bool = True
    ) -> None:
        """
        Update incident with execution result.
        
        Args:
            incident_id: Incident ID
            execution_result: Result of command execution
            is_executed: Whether command was executed
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE incidents 
            SET is_executed = ?, execution_result = ?, execution_timestamp = CURRENT_TIMESTAMP
            WHERE id = ?
        ''', (is_executed, execution_result, incident_id))
        
        conn.commit()
        conn.close()
    
    def get_recent_incidents(self, limit: int = 100) -> List[Dict[str, Any]]:
        """
        Get recent incidents.
        
        Args:
            limit: Maximum number of incidents to return
            
        Returns:
            List of incident dictionaries
        """
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM incidents 
            ORDER BY timestamp DESC 
            LIMIT ?
        ''', (limit,))
        
        incidents = [dict(row) for row in cursor.fetchall()]
        conn.close()
        
        return incidents
    
    def get_statistics(self, days: int = 7) -> Dict[str, Any]:
        """
        Get incident statistics for the last N days.
        
        Args:
            days: Number of days to look back
            
        Returns:
            Dictionary with statistics
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        since = datetime.now() - timedelta(days=days)
        
        # Total incidents
        cursor.execute('''
            SELECT COUNT(*) FROM incidents 
            WHERE timestamp >= ?
        ''', (since,))
        total_incidents = cursor.fetchone()[0]
        
        # Auto-executed incidents
        cursor.execute('''
            SELECT COUNT(*) FROM incidents 
            WHERE timestamp >= ? AND is_auto_executed = 1
        ''', (since,))
        auto_executed = cursor.fetchone()[0]
        
        # Manually executed incidents
        cursor.execute('''
            SELECT COUNT(*) FROM incidents 
            WHERE timestamp >= ? AND is_executed = 1 AND is_auto_executed = 0
        ''', (since,))
        manually_executed = cursor.fetchone()[0]
        
        # Blocked incidents (unsafe)
        cursor.execute('''
            SELECT COUNT(*) FROM incidents 
            WHERE timestamp >= ? AND is_safe = 0
        ''', (since,))
        blocked = cursor.fetchone()[0]
        
        # Risk level distribution
        cursor.execute('''
            SELECT risk_level, COUNT(*) as count 
            FROM incidents 
            WHERE timestamp >= ?
            GROUP BY risk_level
        ''', (since,))
        risk_distribution = {row[0]: row[1] for row in cursor.fetchall()}
        
        # Daily incident count
        cursor.execute('''
            SELECT DATE(timestamp) as date, COUNT(*) as count 
            FROM incidents 
            WHERE timestamp >= ?
            GROUP BY DATE(timestamp)
            ORDER BY date
        ''', (since,))
        daily_counts = [{"date": row[0], "count": row[1]} for row in cursor.fetchall()]
        
        conn.close()
        
        return {
            "total_incidents": total_incidents,
            "auto_executed": auto_executed,
            "manually_executed": manually_executed,
            "blocked": blocked,
            "pending": total_incidents - auto_executed - manually_executed - blocked,
            "risk_distribution": risk_distribution,
            "daily_counts": daily_counts
        }
    
    def cleanup_old_incidents(self, retention_days: int = 30) -> int:
        """
        Delete incidents older than retention period.
        
        Args:
            retention_days: Number of days to retain
            
        Returns:
            Number of deleted incidents
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cutoff = datetime.now() - timedelta(days=retention_days)
        
        cursor.execute('''
            DELETE FROM incidents 
            WHERE timestamp < ?
        ''', (cutoff,))
        
        deleted_count = cursor.rowcount
        conn.commit()
        conn.close()
        
        return deleted_count
