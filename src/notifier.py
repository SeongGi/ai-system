"""
Notifier module for AI-SRE-System.
Handles Slack notifications with interactive buttons.
"""

import requests
import json
from typing import Dict, Any, Optional


class SlackNotifier:
    """Slack notification manager."""
    
    def __init__(self, webhook_url: str, username: str = "AI-SRE-Agent"):
        """
        Initialize Slack notifier.
        
        Args:
            webhook_url: Slack webhook URL
            username: Bot username for messages
        """
        self.webhook_url = webhook_url
        self.username = username
    
    def send_incident_alert(
        self,
        log_line: str,
        ai_command: str,
        is_safe: bool = True,
        risk_level: str = "LOW",
        is_auto: bool = False
    ) -> bool:
        """
        Send incident alert with interactive buttons.
        
        Args:
            log_line: Original log line
            ai_command: AI-generated command
            is_safe: Whether command is safe
            risk_level: Risk level of command
            is_auto: Whether this is an auto-execute notification
            
        Returns:
            True if notification sent successfully
        """
        if is_auto:
            return self._send_auto_execute_notification(
                log_line, ai_command, is_safe, risk_level
            )
        else:
            return self._send_interactive_alert(
                log_line, ai_command, is_safe, risk_level
            )
    
    def _send_interactive_alert(
        self,
        log_line: str,
        ai_command: str,
        is_safe: bool,
        risk_level: str
    ) -> bool:
        """Send interactive alert with execute/ignore buttons."""
        
        # Determine color based on risk level
        color_map = {
            "LOW": "#36A64F",      # Green
            "MEDIUM": "#FFA500",   # Orange
            "HIGH": "#FF6B6B",     # Red
            "CRITICAL": "#8B0000"  # Dark Red
        }
        color = color_map.get(risk_level, "#F44336")
        
        # Add warning emoji if unsafe
        title = "🚨 장애 탐지 및 AI 조치 제안"
        if not is_safe:
            title = "⚠️ 장애 탐지 (보안 위험 포함)"
        
        payload = {
            "username": self.username,
            "text": title,
            "attachments": [{
                "callback_id": "fix",
                "color": color,
                "fields": [
                    {
                        "title": "로그",
                        "value": f"```{log_line[:500]}```",
                        "short": False
                    },
                    {
                        "title": f"AI 제안 (위험도: {risk_level})",
                        "value": f"`{ai_command}`",
                        "short": False
                    }
                ],
                "actions": [
                    {
                        "name": "execute",
                        "text": "✅ 실행",
                        "type": "button",
                        "value": ai_command,
                        "style": "primary"
                    },
                    {
                        "name": "ignore",
                        "text": "❌ 거절",
                        "type": "button",
                        "value": "ignore",
                        "style": "danger"
                    }
                ]
            }]
        }
        
        return self._send_message(payload)
    
    def _send_auto_execute_notification(
        self,
        log_line: str,
        ai_command: str,
        is_safe: bool,
        risk_level: str
    ) -> bool:
        """Send notification for auto-executed command."""
        
        if not is_safe:
            # Auto-execute was blocked due to security
            payload = {
                "username": self.username,
                "text": "⚠️ *자동 조치 차단됨 (보안 위험)*",
                "attachments": [{
                    "color": "#8B0000",
                    "fields": [
                        {
                            "title": "로그",
                            "value": f"```{log_line[:500]}```",
                            "short": False
                        },
                        {
                            "title": "차단된 명령어",
                            "value": f"`{ai_command}`",
                            "short": False
                        },
                        {
                            "title": "위험도",
                            "value": risk_level,
                            "short": True
                        }
                    ]
                }]
            }
        else:
            # Auto-execute notification (result will be sent separately)
            payload = {
                "username": self.username,
                "text": "⚡ *자동 조치 실행 중*",
                "attachments": [{
                    "color": "#FFA500",
                    "fields": [
                        {
                            "title": "로그",
                            "value": f"```{log_line[:500]}```",
                            "short": False
                        },
                        {
                            "title": "실행 명령어",
                            "value": f"`{ai_command}`",
                            "short": False
                        }
                    ]
                }]
            }
        
        return self._send_message(payload)
    
    def send_execution_result(
        self,
        command: str,
        success: bool,
        output: str
    ) -> bool:
        """
        Send command execution result.
        
        Args:
            command: Executed command
            success: Whether execution was successful
            output: Command output
            
        Returns:
            True if notification sent successfully
        """
        icon = "✅" if success else "❌"
        color = "#36A64F" if success else "#FF6B6B"
        status = "성공" if success else "실패"
        
        payload = {
            "username": self.username,
            "text": f"{icon} *명령어 실행 {status}*",
            "attachments": [{
                "color": color,
                "fields": [
                    {
                        "title": "명령어",
                        "value": f"`{command}`",
                        "short": False
                    },
                    {
                        "title": "실행 결과",
                        "value": f"```{output[:1000]}```",
                        "short": False
                    }
                ]
            }]
        }
        
        return self._send_message(payload)
    
    def send_simple_message(self, message: str) -> bool:
        """
        Send simple text message.
        
        Args:
            message: Message to send
            
        Returns:
            True if notification sent successfully
        """
        payload = {
            "username": self.username,
            "text": message
        }
        
        return self._send_message(payload)
    
    def _send_message(self, payload: Dict[str, Any]) -> bool:
        """
        Send message to Slack.
        
        Args:
            payload: Message payload
            
        Returns:
            True if sent successfully
        """
        try:
            response = requests.post(
                self.webhook_url,
                json=payload,
                timeout=10
            )
            return response.status_code == 200
        except Exception as e:
            print(f"Failed to send Slack notification: {e}")
            return False
