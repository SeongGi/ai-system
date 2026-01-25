"""
Main application for AI-SRE-System.
Integrates all modules and provides Flask API endpoints.
"""

import os
import sys
from threading import Thread
from flask import Flask, request, jsonify
import json

# Add src directory to path
sys.path.insert(0, os.path.dirname(__file__))

from config import get_config
from security import SecurityFilter
from database import IncidentDatabase
from ai_analyzer import AIAnalyzer
from executor import CommandExecutor
from notifier import SlackNotifier
from monitor import LogMonitor
from logger import setup_logger


class AIRemediator:
    """Main AI remediation system."""
    
    def __init__(self, config_path: str = "config/config.yaml"):
        """
        Initialize AI remediation system.
        
        Args:
            config_path: Path to configuration file
        """
        # Load configuration
        self.config = get_config(config_path)
        
        # Setup logger
        log_file = self.config.get("logging", "file", default="logs/ai-sre-agent.log")
        log_level = self.config.get("logging", "level", default="INFO")
        max_size_mb = self.config.get("logging", "max_size_mb", default=10)
        backup_count = self.config.get("logging", "backup_count", default=5)
        
        self.logger = setup_logger(
            name="ai-sre-agent",
            log_file=log_file,
            level=log_level,
            max_size_mb=max_size_mb,
            backup_count=backup_count
        )
        
        self.logger.info("Initializing AI-SRE-Agent...")
        
        # Initialize components
        self._init_components()
        
        # Initialize Flask app
        self.app = Flask(__name__)
        self._setup_routes()
    
    def _init_components(self) -> None:
        """Initialize all system components."""
        # Security filter
        blacklist_file = self.config.get_file_path("security", "blacklist_file")
        self.security = SecurityFilter(blacklist_file)
        
        # Database
        db_path = self.config.get_file_path("database", "path")
        self.db = IncidentDatabase(db_path)
        
        # AI Analyzer
        api_key = self.config.get("api", "gemini_api_key")
        model_name = self.config.get("api", "gemini_model")
        prompt_file = self.config.get_file_path("security", "blacklist_file").replace("blacklist.txt", "prompt.txt")
        self.ai = AIAnalyzer(api_key, model_name, prompt_file)
        
        # Command Executor
        timeout = self.config.get("security", "command_timeout", default=15)
        self.executor = CommandExecutor(timeout)
        
        # Slack Notifier
        webhook_url = self.config.get("slack", "webhook_url")
        username = self.config.get("slack", "username", default="AI-SRE-Agent")
        self.notifier = SlackNotifier(webhook_url, username)
        
        # Log Monitor
        monitor_type = self.config.get("monitoring", "type")
        log_path = self.config.get("monitoring", "log_path")
        error_levels = self.config.get("monitoring", "error_levels")
        error_keywords = self.config.get("monitoring", "error_keywords")
        auto_keywords_file = self.config.get_file_path("security", "auto_keywords_file")
        
        self.monitor = LogMonitor(
            monitor_type=monitor_type,
            log_path=log_path,
            error_levels=error_levels,
            error_keywords=error_keywords,
            auto_keywords_file=auto_keywords_file
        )
    
    def _setup_routes(self) -> None:
        """Setup Flask routes."""
        
        @self.app.route('/health', methods=['GET'])
        def health():
            """Health check endpoint."""
            return jsonify({"status": "healthy", "service": "AI-SRE-Agent"})
        
        @self.app.route('/prompt/slack', methods=['POST'])
        def handle_slash_command():
            """Handle Slack slash command for prompt update."""
            user_text = request.form.get('text', '').strip()
            
            prompt_file = self.config.get_file_path("security", "blacklist_file").replace("blacklist.txt", "prompt.txt")
            
            if not user_text:
                # Show current prompt
                try:
                    with open(prompt_file, 'r') as f:
                        current_prompt = f.read().strip()
                    return jsonify({
                        "response_type": "ephemeral",
                        "text": f"현재 프롬프트:\n```{current_prompt}```"
                    })
                except Exception as e:
                    return jsonify({
                        "response_type": "ephemeral",
                        "text": f"프롬프트 로드 실패: {e}"
                    })
            
            # Update prompt
            try:
                with open(prompt_file, 'w') as f:
                    f.write(user_text)
                
                return jsonify({
                    "response_type": "in_channel",
                    "text": f"✅ 프롬프트가 업데이트되었습니다:\n```{user_text[:200]}```"
                })
            except Exception as e:
                return jsonify({
                    "response_type": "ephemeral",
                    "text": f"프롬프트 업데이트 실패: {e}"
                })
        
        @self.app.route('/slack/interactive', methods=['POST'])
        def handle_interactive():
            """Handle Slack interactive button clicks."""
            try:
                payload = json.loads(request.form.get('payload'))
                action = payload['actions'][0]
                command = action['value']
                
                if command == "ignore":
                    return jsonify({
                        "replace_original": True,
                        "text": "🚫 조치가 거절되었습니다."
                    })
                
                # Execute command
                success, output, error = self.executor.execute_with_validation(
                    command, self.security
                )
                
                if error:
                    return jsonify({
                        "replace_original": True,
                        "text": f"❌ 실행 실패\n명령어: `{command}`\n오류: {error}"
                    })
                
                # Send result
                icon = "✅" if success else "⚠️"
                return jsonify({
                    "replace_original": True,
                    "text": f"{icon} *명령어 실행 완료*\n명령어: `{command}`\n결과:\n```{output[:1000]}```"
                })
                
            except Exception as e:
                return jsonify({
                    "replace_original": True,
                    "text": f"❌ 오류 발생: {str(e)}"
                })
        
        @self.app.route('/stats', methods=['GET'])
        def get_stats():
            """Get incident statistics."""
            days = request.args.get('days', default=7, type=int)
            stats = self.db.get_statistics(days)
            return jsonify(stats)
        
        @self.app.route('/incidents', methods=['GET'])
        def get_incidents():
            """Get recent incidents."""
            limit = request.args.get('limit', default=100, type=int)
            incidents = self.db.get_recent_incidents(limit)
            return jsonify(incidents)
    
    def _handle_log_event(self, log_line: str, is_auto: bool) -> None:
        """
        Handle log event from monitor.
        
        Args:
            log_line: Log line that triggered event
            is_auto: Whether to auto-execute
        """
        try:
            # Analyze log with AI
            ai_command = self.ai.analyze_log(log_line)
            
            if not ai_command:
                print(f"[!] Failed to analyze log: {log_line[:100]}")
                return
            
            # Sanitize command
            ai_command = self.security.sanitize_command(ai_command)
            
            # Check safety
            is_safe, reason = self.security.is_safe(ai_command)
            risk_level = self.security.get_risk_level(ai_command)
            
            # Save to database
            incident_id = self.db.add_incident(
                log_line=log_line,
                ai_command=ai_command,
                is_auto_executed=is_auto,
                is_safe=is_safe,
                risk_level=risk_level,
                error_message=reason if not is_safe else None
            )
            
            # Handle auto-execute
            if is_auto:
                if is_safe:
                    # Execute command
                    success, output = self.executor.execute(ai_command)
                    
                    # Update database
                    self.db.update_execution(incident_id, output, is_executed=True)
                    
                    # Send notification
                    self.notifier.send_execution_result(ai_command, success, output)
                else:
                    # Blocked due to security
                    self.notifier.send_incident_alert(
                        log_line, ai_command, is_safe, risk_level, is_auto=True
                    )
            else:
                # Send interactive alert
                self.notifier.send_incident_alert(
                    log_line, ai_command, is_safe, risk_level, is_auto=False
                )
            
        except Exception as e:
            print(f"[!] Error handling log event: {e}")
    
    def start(self) -> None:
        """Start the AI remediation system."""
        # Start log monitoring in background thread
        monitor_thread = Thread(
            target=self.monitor.start,
            args=(self._handle_log_event,),
            daemon=True
        )
        monitor_thread.start()
        
        # Start Flask app
        host = self.config.get("service", "host", default="0.0.0.0")
        port = self.config.get("service", "port", default=5000)
        debug = self.config.get("service", "debug", default=False)
        
        print(f"[*] AI-SRE-Agent starting on {host}:{port}")
        self.app.run(host=host, port=port, debug=debug)


def main():
    """Main entry point."""
    # Get config path from environment or use default
    config_path = os.getenv("CONFIG_PATH", "config/config.yaml")
    
    # Create and start remediation system
    remediation = AIRemediator(config_path)
    remediation.start()


if __name__ == "__main__":
    main()
