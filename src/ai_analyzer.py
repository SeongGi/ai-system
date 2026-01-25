"""
AI Analyzer module for AI-SRE-System.
Handles communication with Google Gemini API for log analysis.
"""

import os
from typing import Optional
from google import genai


class AIAnalyzer:
    """AI analyzer for generating remediation commands."""
    
    def __init__(self, api_key: str, model_name: str, prompt_file: str):
        """
        Initialize AI analyzer.
        
        Args:
            api_key: Google Gemini API key
            model_name: Model name to use
            prompt_file: Path to prompt file
        """
        self.api_key = api_key
        self.model_name = model_name
        self.prompt_file = prompt_file
        self.client = genai.Client(api_key=api_key)
    
    def _load_prompt(self) -> str:
        """
        Load system prompt from file.
        
        Returns:
            System prompt text
        """
        if not os.path.exists(self.prompt_file):
            return "Senior SRE. Provide only one safe bash command to fix the log. No prose."
        
        try:
            with open(self.prompt_file, 'r') as f:
                return f.read().strip()
        except Exception as e:
            print(f"Warning: Failed to load prompt: {e}")
            return "Senior SRE. Provide only one safe bash command to fix the log. No prose."
    
    def analyze_log(self, log_line: str) -> Optional[str]:
        """
        Analyze log line and generate remediation command.
        
        Args:
            log_line: Log line to analyze
            
        Returns:
            AI-generated command or None if analysis failed
        """
        try:
            system_prompt = self._load_prompt()
            full_prompt = f"{system_prompt}\n\nLog: {log_line}"
            
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=full_prompt
            )
            
            if not response or not response.text:
                return None
            
            # Extract command from response
            command = self._extract_command(response.text)
            return command
            
        except Exception as e:
            print(f"Error analyzing log: {e}")
            return None
    
    def _extract_command(self, response_text: str) -> str:
        """
        Extract command from AI response.
        
        Args:
            response_text: Raw response from AI
            
        Returns:
            Extracted command
        """
        # Remove markdown code blocks
        text = response_text.strip()
        
        # Remove ```bash or ``` markers
        if text.startswith('```'):
            lines = text.split('\n')
            # Remove first and last lines if they're markdown markers
            if lines[0].startswith('```'):
                lines = lines[1:]
            if lines and lines[-1].strip() == '```':
                lines = lines[:-1]
            text = '\n'.join(lines)
        
        # Remove backticks
        text = text.replace('`', '')
        
        # Take only the first line (should be a single command)
        command = text.split('\n')[0].strip()
        
        return command
    
    def reload_prompt(self) -> None:
        """Reload prompt from file."""
        # Prompt is loaded on each analysis, so this is a no-op
        # But we keep it for API consistency
        pass
